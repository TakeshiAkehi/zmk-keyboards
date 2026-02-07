# How-To: ZMK Zephyr 3.5 → 4.1 マイグレーション

## Problem

ZMK ファームウェアを Zephyr 3.5 から 4.1 にアップグレードする際、複数の Breaking Changes に対応する必要がある。具体的には：

- NFC ピン設定の DeviceTree への移行
- PMW3610 ドライバーの互換文字列変更
- ボード名の変更（`seeeduino_xiao_ble` → `xiao_ble`）
- Kconfig オプション名の変更

これらを漏れなく対応しないとビルドエラーまたは実行時の不具合が発生する。

## Solution

以下の順序でマイグレーションを実施する：

1. Docker イメージを 4.1 に更新
2. build.yaml のボード名を更新
3. NFC ピン設定を Kconfig から DeviceTree に移行
4. PMW3610 使用時は `-alt` ドライバーに変更
5. 各キーボードでビルド検証

## 変更手順

### Step 1: Docker イメージの更新

**build.py** (または同等のビルドスクリプト) で Docker イメージを更新:

```python
# Before
self.IMAGE = "zmkfirmware/zmk-dev-arm:3.5"

# After
self.IMAGE = "zmkfirmware/zmk-dev-arm:4.1"
```

### Step 2: build.yaml のボード名変更

Zephyr 4.1 でボード命名規則が変更された。

**Before**:
```yaml
include:
  - board: seeeduino_xiao_ble
    shield: my_keyboard_left
```

**After**:
```yaml
include:
  - board: xiao_ble
    shield: my_keyboard_left
```

### Step 3: NFC ピン設定の移行

`CONFIG_NFCT_PINS_AS_GPIOS=y` は Zephyr 4.1 で非推奨。DeviceTree で設定する。

**.conf ファイル** — 以下の行を削除:
```conf
# 削除する
CONFIG_NFCT_PINS_AS_GPIOS=y
```

**.overlay ファイル** — 以下を追加:
```dts
&uicr {
    nfct-pins-as-gpios;
};
```

### Step 4: PMW3610 ドライバーの移行

Zephyr 4.1 には上流の PMW3610 ドライバーが含まれているため、badjeff/zmk-pmw3610-driver を使い続ける場合は代替の compatible 文字列が必要。

#### 4a. Overlay の compatible を変更

**Before**:
```dts
&spi0 {
    trackball: trackball@0 {
        compatible = "pixart,pmw3610";
        // ...
    };
};
```

**After**:
```dts
&spi0 {
    trackball: trackball@0 {
        compatible = "pixart,pmw3610-alt";
        // ...
    };
};
```

#### 4b. Kconfig オプション名を変更

すべての `CONFIG_PMW3610_*` オプションに `_ALT` サフィックスを追加:

```conf
# Before
CONFIG_PMW3610=y
CONFIG_PMW3610_SWAP_XY=y
CONFIG_PMW3610_INVERT_X=y
CONFIG_PMW3610_INVERT_Y=y
CONFIG_PMW3610_SMART_ALGORITHM=y
CONFIG_PMW3610_REPORT_INTERVAL_MIN=12
CONFIG_PMW3610_INIT_POWER_UP_EXTRA_DELAY_MS=300

# After
CONFIG_PMW3610_ALT=y
CONFIG_PMW3610_ALT_SWAP_XY=y
CONFIG_PMW3610_ALT_INVERT_X=y
CONFIG_PMW3610_ALT_INVERT_Y=y
CONFIG_PMW3610_ALT_SMART_ALGORITHM=y
CONFIG_PMW3610_ALT_REPORT_INTERVAL_MIN=12
CONFIG_PMW3610_ALT_INIT_POWER_UP_EXTRA_DELAY_MS=300
```

### Step 5: CONFIG_ZMK_MOUSE の移行

ポインティングデバイスの Kconfig シンボルが変更された:

```conf
# Before
CONFIG_ZMK_MOUSE=y

# After
CONFIG_ZMK_POINTING=y
```

## When to Use

- ZMK キーボードを Zephyr 3.5 から 4.1 にアップグレードする場合
- nRF52840 ベースのボード（Seeed XIAO BLE など）を使用している場合
- PMW3610 トラックボールセンサーを使用している場合

## When NOT to Use

- **サードパーティモジュールが Zephyr 4.1 未対応の場合**
  - `badjeff/zmk-input-behavior-listener`
  - `badjeff/zmk-split-peripheral-input-relay`

  これらは `INPUT_CALLBACK_DEFINE` マクロの引数変更により Zephyr 4.1 でビルド不可。対応までは Zephyr 3.5 を継続使用する。

## Notes

- **サイレント失敗に注意**: Kconfig オプション名を間違えても（例: `CONFIG_PMW3610_INVERT_X` のまま）ビルドは成功するが、設定が無視されてマウスの動作がおかしくなる
- **--init フラグ**: west workspace を初期化済みなら以降のビルドで `--init` は不要
- **zmk_work/ ディレクトリ**: `--init` 実行後は ZMK 4.1 のコードベースが配置される

## Checklist

マイグレーション時に以下を確認:

- [ ] build.py の Docker イメージが 4.1
- [ ] build.yaml のボード名が `xiao_ble`（または新しい名前）
- [ ] `.conf` から `CONFIG_NFCT_PINS_AS_GPIOS=y` を削除
- [ ] `.overlay` に `&uicr { nfct-pins-as-gpios; };` を追加
- [ ] PMW3610 使用時: compatible が `pixart,pmw3610-alt`
- [ ] PMW3610 使用時: 全 Kconfig オプションが `CONFIG_PMW3610_ALT_*`
- [ ] `CONFIG_ZMK_MOUSE` → `CONFIG_ZMK_POINTING`
- [ ] ビルド成功を確認

## References

- [ZMK Zephyr 4.1 Blog Post](https://zmk.dev/blog/2025/12/09/zephyr-4-1)
- [badjeff/zmk-pmw3610-driver](https://github.com/badjeff/zmk-pmw3610-driver)
