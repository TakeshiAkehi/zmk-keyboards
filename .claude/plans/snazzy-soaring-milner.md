# virtual_pointer: LVGL経由の入力パイプライン + リネーム

## Context

現在 `touch_pointer.c` は `INPUT_CALLBACK_DEFINE_NAMED` で chsc6x の ABS イベントを直接受信している。
これを LVGL 経由に変更し、外部から API で ABS 座標を受け取る virtual pointer デバイスにリファクタリングする。
同時に命名を touch_pointer → virtual_pointer に変更。

```
変更後のデータフロー:
chsc6x → lvgl_pointer_input → LVGL indev
  → LV_EVENT_PRESSED/PRESSING/RELEASED on screen
  → status_screen.c: touch_event_cb()
  → vpointer_report_abs(vpointer_dev, x, y, pressed)
  → k_msgq + k_work (display thread → sys workqueue)
  → virtual_pointer: ABS→REL + gesture + inertia
  → input_report_rel/key → touchpad_listener → ZMK HID
```

## 命名規則

| 項目 | 旧 | 新 |
|------|----|----|
| compatible | `zmk,touch-pointer` | `zmk,virtual-pointer` |
| nodelabel | `tpointer` | `vpointer` |
| ファイル | `touch_pointer.c` | `virtual_pointer.c` |
| Kconfig | `ZMK_TOUCH_POINTER` | `ZMK_VIRTUAL_POINTER` |
| コード接頭辞 | `tpointer_` | `vpointer_` |
| ヘッダー | — | `include/virtual_pointer.h` |

## ファイル変更一覧

| ファイル | 操作 |
|---------|------|
| `include/virtual_pointer.h` | **新規** — 公開API |
| `drivers/input/touch_pointer.c` → `virtual_pointer.c` | **リネーム+修正** — INPUT_CALLBACK削除、API追加 |
| `drivers/input/Kconfig` | 修正 — ZMK_TOUCH_POINTER → ZMK_VIRTUAL_POINTER |
| `drivers/input/CMakeLists.txt` | 修正 — ファイル名変更 |
| `dts/bindings/zmk,touch-pointer.yaml` | **削除** |
| `dts/bindings/zmk,virtual-pointer.yaml` | **新規** — input プロパティなし |
| `boards/shields/xiaord/xiaord.overlay` | 修正 — tpointer→vpointer、input削除 |
| `boards/shields/xiaord/xiaord.conf` | 修正 — Kconfig名変更（もしあれば） |
| `src/display/status_screen.c` | 修正 — LVGL touchイベント→vpointer_report_abs |
| `src/display/virtual_buttons.c` | 修正 — tpointer_dev→vpointer_dev |
| `src/display/CMakeLists.txt` | 修正 — includeパス追加 |

## 実装詳細

### 1. `include/virtual_pointer.h`

```c
#ifndef ZMK_VIRTUAL_POINTER_H
#define ZMK_VIRTUAL_POINTER_H
#include <zephyr/device.h>

void vpointer_report_abs(const struct device *dev,
                         int16_t x, int16_t y, bool pressed);
#endif
```

### 2. `virtual_pointer.c` 主要変更

**追加:** abs frame キュー（スレッド安全性確保）
```c
struct vpointer_abs_frame { int16_t x, y; bool pressed; };

// vpointer_data に追加:
struct k_work abs_work;
struct k_msgq abs_msgq;
struct vpointer_abs_frame abs_buf[4];
```

**追加:** public API + work handler
```c
void vpointer_report_abs(const struct device *dev, int16_t x, int16_t y, bool pressed)
{
    struct vpointer_data *data = dev->data;
    struct vpointer_abs_frame frame = {.x = x, .y = y, .pressed = pressed};
    k_msgq_put(&data->abs_msgq, &frame, K_NO_WAIT);
    k_work_submit(&data->abs_work);
}

static void abs_work_handler(struct k_work *work)
{
    // k_msgq_get → vpointer_process_frame() を呼ぶ
}
```

**抽出:** `tpointer_input_cb` の BTN_TOUCH 処理部分 → `vpointer_process_frame(data, x, y, pressed)`

**削除:** `tpointer_input_cb()`, `INPUT_CALLBACK_DEFINE_NAMED` マクロ, `pend_x/pend_y` フィールド

**マクロ変更:**
```c
#define VPOINTER_DEFINE(inst)                                       \
    static struct vpointer_data vpointer_data_##inst;               \
    DEVICE_DT_INST_DEFINE(inst, vpointer_init, NULL,                \
                          &vpointer_data_##inst, NULL,              \
                          POST_KERNEL, CONFIG_INPUT_INIT_PRIORITY, NULL);
DT_INST_FOREACH_STATUS_OKAY(VPOINTER_DEFINE)
```

### 3. `status_screen.c` 変更

```c
#include "virtual_pointer.h"

static const struct device *vpointer_dev = DEVICE_DT_GET(DT_NODELABEL(vpointer));

static void touch_event_cb(lv_event_t *e)
{
    lv_event_code_t code = lv_event_get_code(e);
    lv_indev_t *indev = lv_indev_active();
    if (!indev) return;
    lv_point_t pt;
    lv_indev_get_point(indev, &pt);
    bool pressed = (code == LV_EVENT_PRESSED || code == LV_EVENT_PRESSING);
    vpointer_report_abs(vpointer_dev, (int16_t)pt.x, (int16_t)pt.y, pressed);
}

// zmk_display_status_screen() 内で screen に登録:
lv_obj_add_event_cb(screen, touch_event_cb, LV_EVENT_PRESSED, NULL);
lv_obj_add_event_cb(screen, touch_event_cb, LV_EVENT_PRESSING, NULL);
lv_obj_add_event_cb(screen, touch_event_cb, LV_EVENT_RELEASED, NULL);
```

### 4. overlay 変更

```dts
vpointer: vpointer {
    compatible = "zmk,virtual-pointer";
};

touchpad_listener: touchpad_listener {
    compatible = "zmk,input-listener";
    device = <&vpointer>;
};
```

### 5. DT binding (`zmk,virtual-pointer.yaml`)

```yaml
compatible: "zmk,virtual-pointer"
# プロパティなし — 入力は API 経由
```

### 6. スレッド安全性

LVGL display thread → `vpointer_report_abs()` → k_msgq (ISR-safe) + k_work_submit
→ system workqueue: `abs_work_handler` → `vpointer_process_frame`
→ gesture/inertia work もすべて system workqueue 上 → data 競合なし

## ビルド検証

```bash
./build.sh keyboards/zmk-config-genfish/build.yaml -p \
  --extra /home/ake/soft/zmk-keyboards/zmk_modules/zmk-module-xiaord
```

dongle ターゲットで `virtual_pointer.c` がコンパイルされることを確認。
