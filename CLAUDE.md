# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a ZMK keyboard firmware build environment that enables local Docker-based builds for faster iteration compared to GitHub Actions. Keyboard configurations are stored as git submodules following the [unified-zmk-config-template](https://github.com/zmkfirmware/unified-zmk-config-template) structure.

## Build Commands

```bash
# Build firmware (standard usage)
python build.py keyboards/<keyboard-name>/build.yaml

# First-time setup for a keyboard (initializes west workspace)
python build.py keyboards/<keyboard-name>/build.yaml --init

# Update ZMK sources before building
python build.py keyboards/<keyboard-name>/build.yaml --update

# Force pristine rebuild
python build.py keyboards/<keyboard-name>/build.yaml -p

# Build multiple keyboards at once
python build.py keyboards/zmk-config-fish/build.yaml keyboards/zmk-config-d3kb2/build.yaml
```

Output `.uf2` files are placed in `keyboards/<keyboard-name>/zmk_work/`.

## Adding a New Keyboard

```bash
./add_keyboard.bash <repo-name>
```

This clones the unified-zmk-config-template, initializes a new git repo, pushes to GitHub, and adds it as a submodule.

## Architecture

### Build Flow

1. `build.py` parses `build.yaml` for board/shield combinations
2. Docker container (`zmkfirmware/zmk-dev-arm:3.5`) is started with `zmk_work/` mounted
3. `west init -l config/` initializes the workspace (on `--init`)
4. `west update` fetches ZMK and dependencies
5. `west build` compiles each shield, producing `.uf2` files

### Keyboard Configuration Structure

Each submodule in `keyboards/` follows this structure:
```
zmk-config-<name>/
├── build.yaml              # Build targets (board, shield, cmake-args, artifact-name)
├── config/
│   └── west.yml           # West manifest (ZMK version, extra modules)
├── boards/shields/<name>/ # Shield definitions (.overlay, .keymap, .conf, .dtsi)
└── zmk_work/              # Build workspace (created by build.py)
```

### build.yaml Format

```yaml
include:
  - board: seeeduino_xiao_ble
    shield: my_keyboard_left
  - board: seeeduino_xiao_ble
    shield: my_keyboard_left
    artifact-name: my_keyboard_left_central   # Custom output filename
    cmake-args: -DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y
    snippet: zmk-usb-logging                  # Optional Zephyr snippet
```

### Docker Container Lifecycle

- Container name matches the keyboard config directory name
- Containers are reused unless `--init` creates a fresh one
- `close_all_container.bash` can clean up all containers

## Prerequisites

- Python 3.8+ with `docker` and `pyyaml` packages
- Docker daemon running
- Virtual environment available at `.venv/`
