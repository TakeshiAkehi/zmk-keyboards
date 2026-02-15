#!/usr/bin/env bash
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
readonly DEFAULT_CONTAINER_IMAGE="zmkfirmware/zmk-build-arm:stable"
readonly CONTAINER_IMAGE="${ZMK_DOCKER_IMAGE:-$DEFAULT_CONTAINER_IMAGE}"
readonly SCRIPT_DIR="$(dirname "$(realpath "$0")")"
readonly REPO_ROOT="$SCRIPT_DIR"
readonly WORKFLOW_FILE=".github/workflows/build-local.yml"

# ── State (set by parse_args / setup_paths) ──────────────────────────────────
yaml_file=""
init_flag=false
update_flag=false
pristine_flag=false
target_names=()

# Per-keyboard paths (set by setup_paths)
keyboard_name=""
confdir=""
boardsdir=""
workdir_top=""
workdir=""
wconfdir=""
wboardsdir=""
wbuilddir=""

# ── Utilities ────────────────────────────────────────────────────────────────
log()   { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
error() { printf "[ERROR] %s\n" "$*" >&2; return 1; }

check_dependencies() {
    local missing=false
    for cmd in act yq; do
        if ! command -v "$cmd" &>/dev/null; then
            error "$cmd is required but not found"
            missing=true
        fi
    done
    if ! command -v fzf &>/dev/null; then
        log "warning: fzf not found — interactive selection will be unavailable"
    fi
    $missing && exit 1

    # act requires Docker
    if ! docker info &>/dev/null 2>&1; then
        error "docker daemon is required by act but not running"
        exit 1
    fi

    # Verify yq is Mike Farah's version (not the Python wrapper)
    if ! yq --version 2>&1 | grep -q 'mikefarah\|https://github.com/mikefarah'; then
        log "warning: yq may not be Mike Farah's version — YAML parsing may behave unexpectedly"
    fi
    return 0
}

# ── act Invocation ───────────────────────────────────────────────────────────
act_run() {
    local kb_name="$1" phase="$2"
    local board="${3:-}" shield="${4:-}" snippet="${5:-}"
    local cmake_args="${6:-}" artifact_name="${7:-}" pristine="${8:-false}"

    local -a act_args=(
        workflow_dispatch
        -j build
        -W "$WORKFLOW_FILE"
        --bind
        --pull=false
        --input "keyboard_name=$kb_name"
        --input "phase=$phase"
        --input "container_image=$CONTAINER_IMAGE"
    )

    [[ -n "$board" ]]         && act_args+=(--input "board=$board")
    [[ -n "$shield" ]]        && act_args+=(--input "shield=$shield")
    [[ -n "$snippet" ]]       && act_args+=(--input "snippet=$snippet")
    [[ -n "$cmake_args" ]]    && act_args+=(--input "cmake_args=$cmake_args")
    [[ -n "$artifact_name" ]] && act_args+=(--input "artifact_name=$artifact_name")
    [[ "$pristine" == true ]]  && act_args+=(--input "pristine=true")

    log "act: phase=$phase kb=$kb_name${board:+ board=$board}${shield:+ shield=$shield}"
    act "${act_args[@]}"
}

# ── Argument Parsing ─────────────────────────────────────────────────────────
show_help() {
    cat <<'HELP'
Usage: build.sh [build.yaml [OPTIONS]]

Build ZMK keyboard firmware using act (local GitHub Actions runner).

With no arguments, launches an interactive fzf command builder that lets you
select keyboards, targets, and flags — then generates and executes the commands.

With a build.yaml argument, builds that single keyboard non-interactively.

Options (with build.yaml):
  --init              Create fresh workspace (west init + update)
  --update            Update ZMK sources (west update)
  -p, --pristine      Force pristine rebuild
  -t, --target NAME   Build only targets matching NAME (repeatable)
  -h, --help          Show this help

Environment variables:
  ZMK_DOCKER_IMAGE    Override the container image (default: zmkfirmware/zmk-build-arm:stable)

Examples:
  build.sh                                              # interactive fzf builder
  build.sh keyboards/zmk-config-fish/build.yaml -p
  build.sh --init keyboards/zmk-config-d3kb2/build.yaml
  build.sh keyboards/zmk-config-fish/build.yaml -t fish_left_central -t fish_right
HELP
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init)        init_flag=true ;;
            --update)      update_flag=true ;;
            -p|--pristine) pristine_flag=true ;;
            -t|--target)   shift; target_names+=("$1") ;;
            -h|--help)     show_help; exit 0 ;;
            -*)            error "unknown option: $1" ;;
            *)
                if [[ -n "$yaml_file" ]]; then
                    error "only one build.yaml file allowed (got '$yaml_file' and '$1'). Use interactive mode for multiple keyboards."
                fi
                yaml_file="$1"
                ;;
        esac
        shift
    done

    # Validate that specified file exists
    if [[ -n "$yaml_file" ]]; then
        [[ -f "$yaml_file" ]] || error "file not found: $yaml_file"
    fi
}

# ── fzf Interactive Selection ────────────────────────────────────────────────
select_keyboards() {
    local -a candidates=()
    local f
    for f in "$REPO_ROOT"/keyboards/*/build.yaml; do
        [[ -f "$f" ]] && candidates+=("$f")
    done
    [[ ${#candidates[@]} -eq 0 ]] && error "no build.yaml files found in keyboards/"

    if ! command -v fzf &>/dev/null; then
        error "fzf is required for interactive selection. Specify a build.yaml file as argument instead."
    fi

    local fzf_exit=0
    local result
    result=$(printf '%s\n' "${candidates[@]}" | fzf \
        --multi \
        --prompt="Select keyboard(s)> " \
        --delimiter='/' \
        --with-nth=-2 \
        --preview 'yq eval ".include[].shield" {}' \
        --preview-window=right:30%
    ) || fzf_exit=$?

    if [[ $fzf_exit -ne 0 ]]; then
        return 130
    fi
    printf '%s\n' "$result"
}

# Select specific targets from a build.yaml via fzf.
# Returns space-separated target names, or "" if all are selected.
select_targets_interactive() {
    local yaml_file="$1"
    local -a all_labels=()
    local -a selected_labels=()

    # Collect all target labels
    while IFS='|' read -r _board shield _snippet _cmake_args artifact_name; do
        all_labels+=("${artifact_name:-$shield}")
    done < <(parse_build_yaml "$yaml_file")

    # Present fzf with all selected by default
    local selection
    local kb_name
    kb_name="$(basename "$(dirname "$yaml_file")")"
    local fzf_exit=0
    selection=$(printf '%s\n' "${all_labels[@]}" | fzf \
        --multi \
        --bind 'start:select-all' \
        --header="── $kb_name ──" \
        --prompt="Select target(s)> " \
    ) || fzf_exit=$?

    if [[ $fzf_exit -ne 0 ]]; then
        return 130
    fi

    [[ -z "$selection" ]] && return 0

    mapfile -t selected_labels <<< "$selection"

    # If all selected, return empty (means "all")
    if [[ ${#selected_labels[@]} -eq ${#all_labels[@]} ]]; then
        return 0
    fi

    # Return space-separated names
    printf '%s ' "${selected_labels[@]}" | sed 's/ $//'
}

# Select build flags via fzf.
# Returns space-separated flags, or "" if none selected.
select_flags_interactive() {
    local keyboard_name="$1"
    local selection
    local fzf_exit=0
    selection=$(printf '%s\n' \
        "(none)|No extra flags — build only" \
        "-p|Pristine rebuild (clean build directory)" \
        "--init|Initialize fresh workspace" \
        "--update|Update ZMK sources (west update)" \
    | fzf \
        --multi \
        --header="── $keyboard_name ──" \
        --prompt="Select flags> " \
        --delimiter='|' \
        --with-nth=1.. \
    ) || fzf_exit=$?

    if [[ $fzf_exit -ne 0 ]]; then
        return 130
    fi

    [[ -z "$selection" ]] && return 0

    # Extract just the flag part (before |), skipping (none)
    echo "$selection" | while IFS='|' read -r flag _desc; do
        [[ "$flag" == "(none)" ]] && continue
        printf '%s ' "$flag"
    done | sed 's/ $//'
}

# ── Path Setup ───────────────────────────────────────────────────────────────
setup_paths() {
    local yaml_file
    yaml_file="$(realpath "$1")"

    keyboard_name="$(basename "$(dirname "$yaml_file")")"
    confdir="$(dirname "$yaml_file")/config"
    boardsdir="$(dirname "$yaml_file")/boards"
    workdir_top="$REPO_ROOT/zmk_work/$keyboard_name"
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

# ── Interactive Build (fzf command builder) ─────────────────────────────────
interactive_build() {
    local selected
    if ! selected=$(select_keyboards); then
        log "cancelled"
        exit 0
    fi
    [[ -z "$selected" ]] && exit 0

    local -a yaml_files=()
    mapfile -t yaml_files <<< "$selected"

    # For each yaml: collect targets and flags
    local -a specs=()   # each entry: "yaml_file|target_filter|flags"
    for f in "${yaml_files[@]}"; do
        local kb_name
        kb_name="$(basename "$(dirname "$f")")"

        # Select targets
        local target_filter
        if ! target_filter=$(select_targets_interactive "$f"); then
            log "cancelled"
            exit 0
        fi

        # Select flags
        local flags
        if ! flags=$(select_flags_interactive "$kb_name"); then
            log "cancelled"
            exit 0
        fi

        specs+=("${f}|${target_filter}|${flags}")
    done

    # Build replay command(s)
    local -a replay_parts=()
    for spec in "${specs[@]}"; do
        IFS='|' read -r f target_filter flags <<< "$spec"
        local rel="${f#"$REPO_ROOT"/}"
        local cmd="./build.sh $rel"
        [[ -n "$flags" ]] && cmd+=" $flags"
        if [[ -n "$target_filter" ]]; then
            for t in $target_filter; do
                cmd+=" -t $t"
            done
        fi
        replay_parts+=("$cmd")
    done

    # Save replay command to .last_build
    local last_build="$REPO_ROOT/.last_build"
    {
        printf '#!/usr/bin/env bash\n'
        printf '# Generated by build.sh interactive mode at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'set -euo pipefail\n'
        printf 'cd "%s"\n' "$REPO_ROOT"
        for (( i=0; i<${#replay_parts[@]}; i++ )); do
            printf '%s\n' "${replay_parts[$i]}"
        done
    } > "$last_build"
    chmod +x "$last_build"

    # Print replay command
    if [[ ${#replay_parts[@]} -eq 1 ]]; then
        log "replay: ${replay_parts[0]}"
    else
        log "replay:"
        local i
        for (( i=0; i<${#replay_parts[@]}; i++ )); do
            if (( i < ${#replay_parts[@]} - 1 )); then
                log "  ${replay_parts[$i]} &&"
            else
                log "  ${replay_parts[$i]}"
            fi
        done
    fi
    log "saved to: .last_build (run with ./rebuild.sh)"

    # Execute each spec
    for spec in "${specs[@]}"; do
        IFS='|' read -r f target_filter flags <<< "$spec"

        # Parse flags for this keyboard
        local spec_init=false spec_update=false spec_pristine=false
        for flag in $flags; do
            case "$flag" in
                --init)        spec_init=true ;;
                --update)      spec_update=true ;;
                -p|--pristine) spec_pristine=true ;;
            esac
        done

        log "━━━ processing: $f ━━━"
        [[ "$spec_init" == true ]]                                && builder_init "$f"
        [[ "$spec_update" == true || "$spec_init" == true ]]      && builder_update "$f"
        builder_build "$f" "$spec_pristine" "$target_filter"
    done
}

# ── Build Logic ──────────────────────────────────────────────────────────────
builder_init() {
    local yaml_file="$1"
    setup_paths "$yaml_file"

    if [[ -d "$workdir" ]]; then
        rm -rf "$workdir"
    fi
    mkdir -p "$workdir"
    cp -rT "$confdir" "$wconfdir"

    act_run "$keyboard_name" "init"
}

builder_update() {
    local yaml_file="$1"
    setup_paths "$yaml_file"

    cp -rT "$confdir" "$wconfdir"

    act_run "$keyboard_name" "update"
}

builder_build() {
    local yaml_file="$1" pristine="$2" target_filter="${3:-}"
    setup_paths "$yaml_file"

    if [[ ! -d "$workdir/.west" ]]; then
        error "workspace not initialized: $workdir — run with --init first"
    fi

    mkdir -p "$wbuilddir"
    cp -rT "$boardsdir" "$wboardsdir"

    local targets
    targets=$(parse_build_yaml "$yaml_file")

    # Filter by target names if specified (from -t flags or interactive selection)
    local -a filter_names=()
    if [[ -n "$target_filter" ]]; then
        read -ra filter_names <<< "$target_filter"
    elif [[ ${#target_names[@]} -gt 0 ]]; then
        filter_names=("${target_names[@]}")
    fi

    if [[ ${#filter_names[@]} -gt 0 ]]; then
        local filtered=""
        while IFS='|' read -r board shield snippet cmake_args artifact_name; do
            local label="${artifact_name:-$shield}"
            for name in "${filter_names[@]}"; do
                if [[ "$label" == "$name" ]]; then
                    filtered+="${board}|${shield}|${snippet}|${cmake_args}|${artifact_name}"$'\n'
                    break
                fi
            done
        done <<< "$targets"
        filtered="${filtered%$'\n'}"
        [[ -z "$filtered" ]] && { log "no matching targets — skipping $yaml_file"; return 0; }
        targets="$filtered"
    fi

    log "parsing build targets from: $yaml_file"
    echo "$targets" | while IFS='|' read -r board shield snippet cmake_args artifact_name; do
        log "building $board — $shield"
        [[ -n "$snippet" ]]    && log "  snippet = $snippet"
        [[ -n "$cmake_args" ]] && log "  cmake-args = $cmake_args"

        act_run "$keyboard_name" "build" \
            "$board" "$shield" "$snippet" "$cmake_args" "$artifact_name" "$pristine"
    done
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    check_dependencies

    if [[ -z "$yaml_file" ]]; then
        interactive_build
    else
        log "━━━ processing: $yaml_file ━━━"
        [[ "$init_flag" == true ]]                              && builder_init "$yaml_file"
        [[ "$update_flag" == true || "$init_flag" == true ]]    && builder_update "$yaml_file"
        builder_build "$yaml_file" "$pristine_flag"
    fi

    log "done"
}

main "$@"
