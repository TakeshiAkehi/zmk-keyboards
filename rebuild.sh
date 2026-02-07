#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LAST_BUILD="$SCRIPT_DIR/.last_build"

if [[ ! -f "$LAST_BUILD" ]]; then
    echo "[ERROR] .last_build not found — run ./build.sh interactively first" >&2
    exit 1
fi

echo "[rebuild] executing .last_build ..."
exec "$LAST_BUILD"
