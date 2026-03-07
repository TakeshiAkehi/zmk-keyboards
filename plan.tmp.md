# vmouse仮想入力デバイス + status_screen.c入力処理

## Context

`virtual_buttons.c` が `input_report_key(NULL, ...)` で送出するイベントは、`zmk,input-listener` に届かない（`INPUT_CALLBACK_DEFINE` のデバイスフィルタにより）。DT-backed仮想デバイスを作成し、そのデバイスポインタ経由でイベントを送出することで、ZMKのinput pipelineに統合する。

標準chsc6xドライバ（ABS + BTN_TOUCHのみ出力）を使用する想定。ABS→REL変換、タップ検知、inertial cursorはstatus_screen.c側で実装する。

## Phase 0: chsc6xレポートレート計測

カスタムドライバのGPIO割り込み間隔を実測し、LVGLのtick(10ms=100Hz)で中間点ロストが発生するか確認する。

### 変更: `input_chsc6x_custom.c` の `chsc6x_custom_process()` に追加

```c
// ファイル先頭付近に追加
static uint32_t s_last_report_time;
static uint32_t s_report_count;
static uint32_t s_min_interval = UINT32_MAX;
static uint32_t s_max_interval;
static uint64_t s_sum_interval;

// chsc6x_custom_process() の冒頭に追加
uint32_t now = k_uptime_get_32();
if (s_last_report_time > 0) {
    uint32_t interval = now - s_last_report_time;
    if (interval < s_min_interval) s_min_interval = interval;
    if (interval > s_max_interval) s_max_interval = interval;
    s_sum_interval += interval;
}
s_last_report_time = now;
s_report_count++;

// 100回ごとにログ出力
if (s_report_count % 100 == 0 && s_report_count > 0) {
    LOG_INF("Report rate: count=%u avg=%ums min=%ums max=%ums",
            s_report_count,
            (uint32_t)(s_sum_interval / (s_report_count - 1)),
            s_min_interval, s_max_interval);
}
```

### 確認方法
1. ビルド: `./build.sh keyboards/zmk-config-genfish/build.yaml -p`
2. フラッシュして指でタッチパッドをドラッグ
3. USB loggingまたはRTTでログを確認
4. 平均間隔が10ms以上（≤100Hz）なら中間点ロストなし

---

## Phase 1: vmouse仮想デバイス + 入力処理（Phase 0検証後）

## 実装

### 1. DT binding: `dts/bindings/zmk,virtual-input.yaml`（新規）

```yaml
description: Virtual input device for emitting events from software
compatible: "zmk,virtual-input"
```

### 2. ドライバ: `drivers/input/vmouse_shim.c`（新規）

最小限のデバイスインスタンス定義のみ。ラッパー関数不要（Zephyr APIを直接使用）。

```c
#include <zephyr/device.h>
#define DT_DRV_COMPAT zmk_virtual_input

static int vmouse_init(const struct device *dev) { return 0; }

#define VMOUSE_INST(n) \
    DEVICE_DT_INST_DEFINE(n, vmouse_init, NULL, \
                          NULL, NULL, \
                          POST_KERNEL, CONFIG_INPUT_INIT_PRIORITY, NULL);

DT_INST_FOREACH_STATUS_OKAY(VMOUSE_INST)
```

### 3. ビルド設定

**`drivers/input/Kconfig`** に追加:
```
config ZMK_VIRTUAL_INPUT
    bool "Virtual input device for software-generated events"
    default y
    depends on DT_HAS_ZMK_VIRTUAL_INPUT_ENABLED
```

**`drivers/input/CMakeLists.txt`** に追加:
```cmake
zephyr_library_sources_ifdef(CONFIG_ZMK_VIRTUAL_INPUT vmouse_shim.c)
```

### 4. DTノード: `boards/shields/xiaord/xiaord.overlay` に追加

```dts
vmouse: vmouse {
    compatible = "zmk,virtual-input";
};

vmouse_listener: vmouse_listener {
    compatible = "zmk,input-listener";
    device = <&vmouse>;
};
```

### 5. `virtual_buttons.c` 修正

```c
// ファイルスコープ
static const struct device *vmouse_dev = DEVICE_DT_GET(DT_NODELABEL(vmouse));

// cb_key_btn内: NULL → vmouse_dev に変更
input_report_key(vmouse_dev, key, 1, true, K_NO_WAIT);
```

## 修正対象ファイル

| ファイル | 操作 |
|---------|------|
| `dts/bindings/zmk,virtual-input.yaml` | 新規 |
| `drivers/input/vmouse_shim.c` | 新規 |
| `drivers/input/Kconfig` | 追記 |
| `drivers/input/CMakeLists.txt` | 追記 |
| `boards/shields/xiaord/xiaord.overlay` | 追記 |
| `src/display/virtual_buttons.c` | 修正（NULL → vmouse_dev） |

全パスのプレフィックス: `zmk_modules/zmk-module-xiaord/`

## Verification

```bash
./build.sh keyboards/zmk-config-genfish/build.yaml -p
```
コンパイルエラーなしでビルドが通ること。
