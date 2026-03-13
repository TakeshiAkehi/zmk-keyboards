# ZMK Firmware Build Automation

## Overview
This script automates the process of building firmware for ZMK-based keyboard configurations using Docker containers. It handles initializing, updating, and building firmware from configuration files. An fzf-based interactive selection allows quick keyboard selection without memorizing paths.

## Prerequisites

Ensure you have the following installed on your system:

- Docker
- [yq](https://github.com/mikefarah/yq) (Mike Farah version) — for YAML parsing
- [fzf](https://github.com/junegunn/fzf) — for interactive keyboard selection (optional)

## Usage

### Running the Script

```sh
# Interactive selection (fzf) — just run with no arguments
./build.sh

# Specify a build.yaml directly
./build.sh keyboards/zmk-config-fish/build.yaml -p
```

### Options

| Option | Description |
|--------|-------------|
| `--init` | Create fresh workspace and container (first-time setup) |
| `--update` | Update ZMK sources (`west update`) |
| `-p`, `--pristine` | Force pristine rebuild |
| `-t NAME`, `--target NAME` | Build only targets matching NAME (repeatable) |
| `--extra PATH` | Inject a local ZMK module from `zmk_modules/` (repeatable) |
| `-h`, `--help` | Show help |

### Examples

```sh
# First-time setup for a new keyboard
./build.sh --init keyboards/zmk-config-d3kb2/build.yaml

# Rebuild after keymap change (most common)
./build.sh keyboards/zmk-config-fish/build.yaml -p

# Build a single target
./build.sh keyboards/zmk-config-fish/build.yaml -p -t fish_dongle

# Build with a local module override
./build.sh keyboards/zmk-config-fish/build.yaml -p -t fish_dongle --extra zmk_modules/zmk-module-xiaord

# Update ZMK sources after editing west.yml
./build.sh --update keyboards/zmk-config-fish/build.yaml

# Build multiple keyboards at once
./build.sh keyboards/zmk-config-fish/build.yaml keyboards/zmk-config-d3kb2/build.yaml -p

# Interactive selection with fzf (Tab for multi-select)
./build.sh
```

## Project Structure

```plaintext
.
├── build.sh                # Main build script (bash/zsh)
├── add_keyboard.bash       # Scaffold a new keyboard submodule
├── close_all_container.bash # Remove all build containers
├── keyboards/
│   ├── zmk-config-d3kb2/   # Keyboard configuration (git submodule)
│   │   ├── build.yaml      # Build targets
│   │   ├── boards/         # Board/shield definitions
│   │   └── config/
│   │       └── west.yml    # West manifest (ZMK version, modules)
│   └── zmk-config-fish/    # Another keyboard
├── zmk_work/               # Build workspaces (per keyboard, gitignored)
│   ├── zmk-config-d3kb2/
│   └── zmk-config-fish/
├── zmk_modules/            # ZMK module submodules
│   └── zmk-module-xiaord/  # Xiaord round-display module (git submodule)
└── context_doc/            # Architecture decision records and design docs
```

## How It Works

1. **Container Setup**
   - A Docker container (`zmkfirmware/zmk-dev-arm:4.1`) is created per keyboard.
   - `zmk_work/<keyboard-name>/` is mounted read-write for the build workspace.
   - Containers are reused across builds unless `--init` is specified.

2. **Initialization (`--init`)**
   - Creates a fresh workspace at `zmk_work/<keyboard-name>/zmk/`.
   - Copies `config/` into the workspace and runs `west init -l`.
   - Followed automatically by `west update` and a build.

3. **Updating (`--update`)**
   - Copies the latest `config/` and runs `west update` to fetch dependencies.

4. **Building Firmware**
   - Board and shield combinations are parsed from `build.yaml` using `yq`.
   - `west build` runs inside the container for each target.
   - Output `.uf2` files are copied to `zmk_work/<keyboard-name>/`.

## Local Module Injection

`zmk_modules/` contains ZMK module submodules tracked in this repository.
Modules are injected into builds using the `--extra` flag:

```sh
./build.sh keyboards/zmk-config-fish/build.yaml -p -t fish_dongle \
    --extra zmk_modules/zmk-module-xiaord
```

The `--extra` flag can be repeated for multiple modules. In interactive mode,
an fzf picker lists available modules from `zmk_modules/`.

Each module must contain a `zephyr/module.yml`. The `zmk_modules/` directory
is mounted read-only inside the build container.

## Example YAML Configuration

An example `build.yaml` file that defines build targets:

```yaml
include:
  - board: nice_nano_v2
    shield: my_keyboard_left
  - board: nice_nano_v2
    shield: my_keyboard_right
  - board: seeeduino_xiao_ble
    shield: my_keyboard_left
    artifact-name: my_keyboard_left_central
    cmake-args: -DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y
    snippet: zmk-usb-logging
```

## Troubleshooting

### Docker Issues
- Ensure Docker is running before executing the script.
- If a container is already running, the script will reuse it unless `--init` is specified.
- Use `./close_all_container.bash` to remove all build containers.

### Build Failures
- If the firmware build fails, check if `zmk.uf2` was generated in `zmk_work/<keyboard-name>/zmk/build/<shield>/zephyr/`.
- Ensure all board and shield definitions are correct in `build.yaml`.
- Try a pristine rebuild with `-p`.

### Platform Notes
- Uses `cp -rT` (GNU coreutils) — does not work on macOS.

## License
This project is open-source and provided under the MIT license.