# ZMK Keyboards Project Memory

## Project Overview
ZMK keyboard firmware build environment using `act` to run GitHub Actions locally.
Keyboard configs in `keyboards/` as git submodules. Build with `./build.sh`.

## Key Paths
- Build script: `./build.sh`
- Keyboard configs: `keyboards/<name>/build.yaml`
- Build outputs: `zmk_work/<name>/`
- Local modules: `zmk_modules/` (gitignored, bind-mounted into act container)
- Module submodule: `zmk_modules/zmk-module-xiaord/`

## Build Commands
```bash
# Standard build
./build.sh keyboards/zmk-config-genfish/build.yaml -p

# With local module override (zmk-module-xiaord)
./build.sh keyboards/zmk-config-genfish/build.yaml -p --extra /home/ake/soft/zmk-keyboards/zmk_modules/zmk-module-xiaord
```

## zmk-module-xiaord Architecture (as of Feb 28, 2026)

### Touch Input Pipeline
```
chsc6x (standard driver) → ABS_X/Y + BTN_TOUCH events
    → touch_pointer.c (INPUT_CALLBACK_DEFINE_NAMED on chsc6x device)
    → REL_X/Y + BTN_0/BTN_1 events as tpointer device
    → touchpad_listener (zmk,input-listener on tpointer)
    → ZMK HID subsystem
```

### Display Directory Structure (after Mar 8, 2026 refactor)
```
src/display/
├── status_screen.c          # エントリポイント・ページ管理
├── page_iface.h             # struct page_ops, PAGE_HOME/CLOCK/BT
├── display_api.h            # ss_navigate_to, ss_fire_behavior, input_virtual_code
├── xiaord_input_codes.h
├── CMakeLists.txt           # add_subdirectory() + zephyr_include_directories
├── listeners/
│   ├── endpoint_status.c/h  # 統合エンドポイントリスナー + endpoint_status_register_cb
│   └── battery_status.c/h   # peripheral batteryリスナー
├── ui/
│   ├── ui_btn.c/h           # ボタンファクトリ + circle layout
│   ├── sym_lookup.h         # input code → LVGLシンボル変換
│   ├── home_buttons.c/h     # ホーム画面ボタンリング
│   └── bg/bg1.c/bg2.c/bg3.c
└── pages/
    ├── page_home.c          # home_endpoint_cb + battery_status_init
    ├── page_bt.c            # bt_endpoint_cb (label + profile buttons)
    └── page_clock.c
```
CMakeLists includes `listeners/` and `ui/` via `zephyr_include_directories` — no relative paths in sources.

### Key Files (drivers)
- `drivers/input/virtual_key_source.c` — Active driver: emits INPUT_KEY_x; cursor logic in #if 0
- `drivers/input/virtual_pointer.c` — Legacy cursor driver (not compiled, preserved for reference)
- `dts/bindings/zmk,virtual-key-source.yaml` — Active DT binding
- `boards/shields/xiaord/xiaord.overlay` — DT config (vkey node, touchpad_listener→vkey)
- `boards/shields/xiaord/xiaord.conf` — Kconfig: `CONFIG_ZMK_VIRTUAL_KEY_SOURCE` auto via DT_HAS_...

## Multi-page Tileview Architecture (Mar 1, 2026)

### Page Layout (PAGE_HOME=0, PAGE_CLOCK=1, PAGE_MACROPAD=2)
- Home `mouse_active=true` — full-screen virtual pointer surface
- Clock `mouse_active=false` — HH:MM (Montserrat 48) + YYYY-MM-DD, Back→HOME, ▶→MACROPAD
- Macropad `mouse_active=false` — native LVGL buttons

### Touch Routing
Touch is handled entirely by LVGL. No virtual pointer cursor routing.
`ss_send_key()` calls `input_report_key()` directly on the `vkey` device.

### Navigation
- Long-press menu button (LV_SYMBOL_LIST) on home → `ss_navigate_to(PAGE_CLOCK)`
- Navigate between pages via `ss_navigate_to(page_idx)`

### Kconfig
- `CONFIG_ZMK_VIRTUAL_KEY_SOURCE=y` (auto via DT_HAS_ZMK_VIRTUAL_KEY_SOURCE_ENABLED)
- `CONFIG_LV_USE_TILEVIEW=y` required in xiaord.conf

### CMakeLists Rule (critical)
Always use `zephyr_library_sources_ifdef(CONFIG_xxx file.c)` for driver files that use
Kconfig macros. Unconditional compilation fails for peripheral builds that don't enable
the relevant Kconfig options.

### Naming Convention
| Item | Name |
|------|------|
| DT compatible | `zmk,virtual-key-source` |
| DT nodelabel | `vkey` |
| Driver file | `virtual_key_source.c` |
| Kconfig | `ZMK_VIRTUAL_KEY_SOURCE` |
| Old cursor driver | `virtual_pointer.c` (preserved, not compiled) |

### Multi-instance Pattern
Follows Zephyr input_longpress.c convention:
```c
INPUT_CALLBACK_DEFINE_NAMED(
    DEVICE_DT_GET_OR_NULL(DT_INST_PHANDLE(inst, input)),
    tpointer_input_cb,
    (void *)DEVICE_DT_INST_GET(inst),
    tpointer_cb_##inst);
```

## Workflow Rules
- After implementing changes, **always build** to verify no errors before reporting done.
- Build command for fish_dongle: `./build.sh keyboards/zmk-config-fish/build.yaml -p -t fish_dongle --extra /home/ake/soft/zmk-keyboards/zmk_modules/zmk-module-xiaord`

## Previously Implemented

### Phase 0
- CHSC6X touchpad: no intermediate point drops verified
- Standard chsc6x driver emits ABS_X/Y (no sync) + BTN_TOUCH (sync=true) per frame

### RTC Time-Set UI (Mar 1, 2026)
- `page_clock.c`: 2-container show/hide design (`s_cont_display` / `s_cont_edit`)
- Edit mode: 5 LVGL rollers (HH/MM/YYYY/Mon/Day) + Cancel/OK buttons
- `enter_edit_mode()` populates rollers from current RTC or defaults to 2026-01-01 00:00
- `leave_edit_mode()` resumes timer; `page_clock_leave()` always pauses timer after
- Sakamoto's algorithm for `tm_wday` (required by PCF8563 driver)
- Year roller range: 2024–2035 (`LV_ROLLER_MODE_NORMAL`)
- Hour/Minute rollers: `LV_ROLLER_MODE_INFINITE`
