# xiaord ディスプレイサポート実装計画

参考: [prospector-zmk-module](https://github.com/carrefinho/prospector-zmk-module)

---

## ディスプレイサポートの全体像

### ハードウェア比較

| | Prospector | xiaord (Seeed XIAO Round) |
|---|---|---|
| ディスプレイコントローラ | ST7789V | GC9X01X (GC9A01) |
| インターフェース | SPI | SPI |
| 解像度 | 240×320 | 240×240 (円形) |
| タッチ | なし | CHSC6X (I2C) |

### ZMK ディスプレイスタック（必要な層）

```
┌─────────────────────────────────────┐
│  Custom Status Screen (LVGL widgets)│  ← 任意：独自UI
├─────────────────────────────────────┤
│  ZMK Display subsystem              │  ← CONFIG_ZMK_DISPLAY=y
├─────────────────────────────────────┤
│  LVGL                               │  ← lvgl dep (module.yml 既存)
├─────────────────────────────────────┤
│  Display driver (GC9X01X)           │  ← seeed_xiao_round_display が提供
├─────────────────────────────────────┤
│  SPI / GPIO                         │  ← ハードウェア
└─────────────────────────────────────┘
```

---

## 必要な変更（xiaord モジュール）

### 1. `xiaord.overlay` への追加

```devicetree
/ {
    chosen {
        zephyr,display = &gc9x01x;  // seeed_xiao_round_display が定義するノード名
    };
};
```

Prospector との違い：`&st7789` → `&gc9x01x`（ボード依存）

### 2. `xiaord.conf` への追加

```kconfig
# ディスプレイ有効化
CONFIG_ZMK_DISPLAY=y

# カスタムステータス画面（独自UIを作る場合）
# CONFIG_ZMK_DISPLAY_STATUS_SCREEN_CUSTOM=y

# LVGL バッファ・メモリ設定
CONFIG_LV_Z_VDB_SIZE=50
CONFIG_LV_Z_MEM_POOL_SIZE=10000

# カラー設定（GC9X01X は RGB565）
CONFIG_LV_COLOR_DEPTH_16=y

# リフレッシュ周期
CONFIG_ZMK_DISPLAY_REFRESH_PERIOD_MS=20

# スレッドスタック
CONFIG_ZMK_DISPLAY_DEDICATED_THREAD_STACK_SIZE=4096

# 使用するLVGLウィジェット（必要なものを選択）
CONFIG_LV_USE_LABEL=y
CONFIG_LV_USE_IMG=y
CONFIG_LV_USE_ARC=y
```

### 3. `module.yml`（既存のまま使用可能）

```yaml
name: zmk-module-xiaord
build:
  cmake: .
  kconfig: Kconfig
  settings:
    board_root: .
    dts_root: .
  depends:
    - lvgl   # ← 既に記載済み
```

### 4. 独自ステータス画面（任意）

Prospector は `src/` 以下でカスタムUIを実装している：

```
src/
├── custom_status_screen.c  # LVGLウィジェット配置
├── brightness.c            # 輝度制御
├── display_rotate_init.c   # 画面回転
├── fonts/
└── widgets/
```

これを再現するには `CONFIG_ZMK_DISPLAY_STATUS_SCREEN_CUSTOM=y` を有効にし、`zmk_display_status_screen()` を実装する必要がある。

### 5. LVGL カスタマイズ（任意）

Prospector は `modules/lvgl/lvgl.c` でZephyr標準のlvgl.cを置き換えている（バッファ管理のカスタマイズ）。基本的な表示だけなら不要。

---

## Prospector との構造差分

```
prospector-zmk-module/          xiaord に追加する場合
├── drivers/display/            不要（GC9X01X はZMK既存ドライバ使用）
│   ├── display_st7789v.c
│   └── ...
├── modules/lvgl/               任意（高度なカスタマイズ時のみ）
├── boards/shields/prospector/
│   ├── prospector.overlay      → xiaord.overlay に chosen 追加
│   ├── Kconfig.defconfig       → xiaord のKconfigに CONFIG_ZMK_DISPLAY 追加
│   └── src/                   任意（カスタムUI作る場合）
└── zephyr/module.yml           既存のものでOK
```

---

## 実装の優先順位

| ステップ | 内容 | 難易度 |
|---|---|---|
| 1 | `xiaord.conf` に `CONFIG_ZMK_DISPLAY=y` と LVGL 設定追加 | 低 |
| 2 | `xiaord.overlay` に `zephyr,display` chosen 追加 | 低 |
| 3 | ビルド確認・デフォルトステータス画面の動作確認 | 中 |
| 4 | カスタムステータス画面の実装（LVGL widgets） | 高 |
| 5 | タッチ入力とディスプレイUIの連携 | 高 |

---

## 備考・インサイト

- `seeed_xiao_round_display` シールドが既に GC9X01X ドライバを設定しているため、Prospector のように独自ドライバを書く必要はない。必要なのは `zephyr,display` のマッピングと ZMK 表示サブシステムの有効化のみ
- Prospector の LVGL オーバーライド（`modules/lvgl/lvgl.c`）は、ZMK 標準の lvgl.c をビルドから除外し独自版に差し替えるテクニック。`zephyr_library_amend()` + `HEADER_FILE_ONLY` プロパティで実現
- 円形ディスプレイ（240×240）では LVGL の `LV_DISP_ROT_NONE` で動作するが、表示コンテンツが矩形前提の場合は `display_rotate_init.c` のような回転初期化が有効
