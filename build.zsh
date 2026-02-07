#!/usr/bin/env zsh
set -eu

# ── Constants ────────────────────────────────────────────────────────────────
typeset -r DOCKER_IMAGE="zmkfirmware/zmk-dev-arm:4.1"
typeset -r SCRIPT_DIR="${0:A:h}"
typeset -r REPO_ROOT="${SCRIPT_DIR}"
typeset -r ZMK_MODULES_DIR="$REPO_ROOT/zmk_modules"

# ── State (set by parse_args / setup_paths) ──────────────────────────────────
typeset -a yaml_files=()
typeset    init_flag=false
typeset    update_flag=false
typeset    pristine_flag=false

# Per-keyboard paths (set by setup_paths)
typeset container_name=""
typeset confdir=""
typeset boardsdir=""
typeset workdir_top=""
typeset workdir=""
typeset wconfdir=""
typeset wboardsdir=""
typeset wbuilddir=""

# ── Utilities ────────────────────────────────────────────────────────────────
log()   { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" }
error() { printf "[ERROR] %s\n" "$*" >&2; return 1 }

check_dependencies() {
    local missing=false
    for cmd in docker yq; do
        if ! command -v "$cmd" &>/dev/null; then
            error "$cmd is required but not found"
            missing=true
        fi
    done
    if ! command -v fzf &>/dev/null; then
        log "warning: fzf not found — interactive selection will be unavailable"
    fi
    $missing && exit 1

    # Verify yq is Mike Farah's version (not the Python wrapper)
    if ! yq --version 2>&1 | grep -q 'mikefarah\|https://github.com/mikefarah'; then
        log "warning: yq may not be Mike Farah's version — YAML parsing may behave unexpectedly"
    fi
    return 0
}

detect_local_modules() {
    [[ ! -d "$ZMK_MODULES_DIR" ]] && return 0
    local -a paths=()
    for d in "$ZMK_MODULES_DIR"/*(/N); do
        if [[ -f "$d/zephyr/module.yml" ]]; then
            paths+=("$d")
            log "  local module: ${d:t}"
        fi
    done
    (( ${#paths[@]} > 0 )) && printf '%s' "${(j:;:)paths}"
}

# ── Argument Parsing ─────────────────────────────────────────────────────────
show_help() {
    cat <<'HELP'
Usage: build.zsh [OPTIONS] [build.yaml ...]

Build ZMK keyboard firmware using Docker containers.
If no build.yaml files are given, launches fzf for interactive selection.

Options:
  --init        Create fresh workspace and container
  --update      Update ZMK sources (west update)
  -p, --pristine  Force pristine rebuild
  -h, --help      Show this help

Examples:
  build.zsh keyboards/zmk-config-fish/build.yaml -p
  build.zsh --init keyboards/zmk-config-d3kb2/build.yaml
  build.zsh                                        # interactive fzf selection
HELP
}

parse_args() {
    local -a opts_init opts_update opts_pristine opts_help
    zparseopts -D -E \
        -init=opts_init \
        -update=opts_update \
        p=opts_pristine -pristine=opts_pristine \
        h=opts_help -help=opts_help

    [[ ${#opts_help} -gt 0 ]] && { show_help; exit 0 }
    [[ ${#opts_init} -gt 0 ]] && init_flag=true
    [[ ${#opts_update} -gt 0 ]] && update_flag=true
    [[ ${#opts_pristine} -gt 0 ]] && pristine_flag=true

    # Remaining positional args are yaml files
    yaml_files=("$@")

    # Validate that specified files exist
    for f in "${yaml_files[@]}"; do
        [[ -f "$f" ]] || error "file not found: $f"
    done
}

# ── fzf Interactive Selection ────────────────────────────────────────────────
select_keyboards() {
    local -a candidates=()
    for f in "$REPO_ROOT"/keyboards/*/build.yaml(N); do
        candidates+=("$f")
    done
    [[ ${#candidates} -eq 0 ]] && error "no build.yaml files found in keyboards/"

    if ! command -v fzf &>/dev/null; then
        error "fzf is required for interactive selection. Specify build.yaml files as arguments instead."
    fi

    printf '%s\n' "${candidates[@]}" | fzf \
        --multi \
        --prompt="Select keyboard(s)> " \
        --preview 'yq eval ".include[].shield" {}' \
        --preview-window=right:30%
}

# ── Docker Container Management ──────────────────────────────────────────────
container_ensure() {
    local name="$1" mount="$2" force_new="${3:-false}" _recurse="${4:-false}"

    # Pull image if missing
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qF "$DOCKER_IMAGE"; then
        log "pulling $DOCKER_IMAGE ..."
        docker pull "$DOCKER_IMAGE"
    fi

    # Force new: remove existing
    if [[ "$force_new" == true ]]; then
        container_remove "$name"
    fi

    # Check current state
    local state
    state=$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null) || state="not_found"

    case "$state" in
        running|exited|created)
            # Verify zmk_modules mount if the directory exists
            if [[ "$_recurse" == false ]] && [[ -d "$ZMK_MODULES_DIR" ]]; then
                local mounts
                mounts=$(docker inspect --format '{{json .Mounts}}' "$name")
                if ! echo "$mounts" | grep -q "$ZMK_MODULES_DIR"; then
                    log "container missing zmk_modules mount — recreating"
                    container_remove "$name"
                    container_ensure "$name" "$mount" false true
                    return $?
                fi
            fi
            if [[ "$state" == "running" ]]; then
                log "container already running: $name"
            else
                log "starting existing container: $name"
                docker start "$name" >/dev/null
                _wait_container_running "$name"
            fi
            ;;
        not_found)
            log "creating new container: $name"
            local -a vol_args=("-v" "${mount}:${mount}")
            if [[ -d "$ZMK_MODULES_DIR" ]]; then
                vol_args+=("-v" "$ZMK_MODULES_DIR:$ZMK_MODULES_DIR:ro")
            fi
            docker run -d \
                --name "$name" \
                "${vol_args[@]}" \
                -w "$mount" \
                "$DOCKER_IMAGE" \
                tail -F /dev/null >/dev/null
            _wait_container_running "$name"
            ;;
        *)
            error "unexpected container state: $state"
            ;;
    esac
}

_wait_container_running() {
    local name="$1"
    local tries=0
    while [[ $(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null) != "running" ]]; do
        sleep 1
        (( tries++ ))
        [[ $tries -ge 30 ]] && error "container $name did not start within 30s"
    done
}

container_remove() {
    local name="$1"
    if docker inspect "$name" &>/dev/null; then
        log "removing existing container: $name"
        docker stop "$name" &>/dev/null || true
        docker rm "$name" &>/dev/null || true
    fi
}

docker_exec() {
    local name="$1" wd="$2"
    shift 2
    log "executing: $*"
    docker exec -w "$wd" "$name" sh -c "$*"
}

# ── Path Setup ───────────────────────────────────────────────────────────────
setup_paths() {
    local yaml_file="${1:A}"

    container_name="${yaml_file:h:t}"
    confdir="${yaml_file:h}/config"
    boardsdir="${yaml_file:h}/boards"
    workdir_top="$REPO_ROOT/zmk_work/$container_name"
    workdir="$workdir_top/zmk"
    wconfdir="$workdir/config"
    wboardsdir="$wconfdir/boards"
    wbuilddir="$workdir/build"

    [[ -d "$boardsdir" ]] || error "boards directory not found: $boardsdir"
    [[ -d "$confdir" ]]   || error "config directory not found: $confdir"

    mkdir -p "$workdir_top"
}

# ── YAML Parsing ─────────────────────────────────────────────────────────────
parse_build_yaml() {
    local yaml_file="$1"
    yq eval '.include[] |
        (.board // "") + "|" +
        (.shield // "") + "|" +
        (.snippet // "") + "|" +
        (.["cmake-args"] // "") + "|" +
        (.["artifact-name"] // "")' "$yaml_file"
}

# ── Build Logic ──────────────────────────────────────────────────────────────
builder_init() {
    local yaml_file="$1"
    setup_paths "$yaml_file"
    container_ensure "$container_name" "$workdir_top" true

    if [[ -d "$workdir" ]]; then
        docker_exec "$container_name" "$workdir" "chmod 777 -R ."
        rm -rf "$workdir"
    fi
    mkdir -p "$workdir"
    cp -rT "$confdir" "$wconfdir"
    docker_exec "$container_name" "$workdir" "west init -l $wconfdir"
}

builder_update() {
    local yaml_file="$1"
    setup_paths "$yaml_file"
    container_ensure "$container_name" "$workdir_top" false

    cp -rT "$confdir" "$wconfdir"
    docker_exec "$container_name" "$workdir" "west update"
}

builder_build() {
    local yaml_file="$1" pristine="$2"
    setup_paths "$yaml_file"

    if [[ ! -d "$workdir/.west" ]]; then
        error "workspace not initialized: $workdir — run with --init first"
    fi

    container_ensure "$container_name" "$workdir_top" false

    mkdir -p "$wbuilddir"
    docker_exec "$container_name" "$workdir" "west zephyr-export"
    cp -rT "$boardsdir" "$wboardsdir"

    local extra_modules
    extra_modules=$(detect_local_modules)

    log "parsing build targets from: $yaml_file"
    parse_build_yaml "$yaml_file" | while IFS='|' read -r board shield snippet cmake_args artifact_name; do
        log "building $board — $shield"
        [[ -n "$snippet" ]]    && log "  snippet = $snippet"
        [[ -n "$cmake_args" ]] && log "  cmake-args = $cmake_args"

        build_target "$board" "$shield" "$snippet" "$cmake_args" "$artifact_name" "$pristine" "$extra_modules"
    done
}

build_target() {
    local board="$1" shield="$2" snippet="$3" cmake_args="$4" artifact_name="$5" pristine="$6" extra_modules="$7"
    local appdir="$workdir/zmk/app"
    local builddir="$wbuilddir/$shield"

    # Construct west build command
    local cmd="west build"
    [[ "$pristine" == true ]] && cmd+=" -p"
    cmd+=" -s $appdir -b $board -d $builddir"
    [[ -n "$snippet" ]] && cmd+=" -S $snippet"
    cmd+=" -- -DSHIELD=$shield -DZMK_CONFIG=$wconfdir"
    if [[ -n "$extra_modules" ]]; then
        cmd+=" '-DEXTRA_ZEPHYR_MODULES=$extra_modules'"
    fi
    [[ -n "$cmake_args" ]] && cmd+=" $cmake_args"

    log "==build=="
    log " workdir = $workdir"
    log " cmd = $cmd"
    docker_exec "$container_name" "$workdir" "$cmd"

    # Fix permissions and copy .uf2 output
    docker_exec "$container_name" "$builddir" "chmod 777 -R ."
    local uf2="$builddir/zephyr/zmk.uf2"
    if [[ -f "$uf2" ]]; then
        local tgt_name="${artifact_name:-$shield}"
        cp "$uf2" "$workdir_top/${tgt_name}.uf2"
        log "copied: ${tgt_name}.uf2"
    else
        error "build failed — uf2 not found: $uf2"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    check_dependencies

    # Interactive selection when no yaml files specified
    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        local selected
        selected=$(select_keyboards)
        [[ -z "$selected" ]] && exit 0
        yaml_files=("${(@f)selected}")
    fi

    for yaml_file in "${yaml_files[@]}"; do
        log "━━━ processing: $yaml_file ━━━"
        [[ "$init_flag" == true ]]                              && builder_init "$yaml_file"
        [[ "$update_flag" == true || "$init_flag" == true ]]    && builder_update "$yaml_file"
        builder_build "$yaml_file" "$pristine_flag"
    done

    log "done"
}

main "$@"
