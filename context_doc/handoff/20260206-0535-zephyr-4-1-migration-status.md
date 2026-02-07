# Handoff: ZMK Zephyr 4.1 マイグレーション作業状況

**Date**: 2026-02-06 05:35
**Session**: ZMK キーボードファームウェアの Zephyr 3.5 → 4.1 マイグレーション

## Summary

ZMK キーボードファームウェアを Zephyr 3.5 から 4.1 にマイグレーションする作業を実施。5台のキーボードのうち3台（d3kb, taiyaki, fish）は正常にビルドが完了。残り2台（s3kb, d3kb2）はサードパーティモジュールの Zephyr 4.1 非互換によりスキップ。

## Current State

### Completed

- [x] build.py の Docker イメージを 3.5 → 4.1 に更新
- [x] 全キーボードの NFC ピン設定を Kconfig から DeviceTree に移行
- [x] PMW3610 ドライバーを `pmw3610-alt` に変更
- [x] ボード名を `seeeduino_xiao_ble` → `xiao_ble` に変更（全5キーボード）
- [x] PMW3610 の Kconfig オプション名を `_ALT` サフィックス付きに変更
- [x] `CONFIG_ZMK_MOUSE` → `CONFIG_ZMK_POINTING` に変更
- [x] d3kb: ビルド成功
- [x] taiyaki: ビルド成功
- [x] fish: ビルド成功

### Skipped (Zephyr 4.1 未対応)

- [ ] s3kb — `zmk-input-behavior-listener` が Zephyr 4.1 未対応
- [ ] d3kb2 — 同上

### Not Started

- [ ] s3kb, d3kb2 のサードパーティモジュール対応待ち

## Key Decisions Made

1. **s3kb と d3kb2 のマイグレーションをスキップ**: `badjeff/zmk-input-behavior-listener` と `badjeff/zmk-split-peripheral-input-relay` が `INPUT_CALLBACK_DEFINE` マクロの引数変更により Zephyr 4.1 でビルド不可。これらのモジュールが対応するまで Zephyr 3.5 を継続使用。

2. **PMW3610 の代替ドライバー使用**: Zephyr 4.1 に上流の PMW3610 ドライバーが含まれているため、badjeff/zmk-pmw3610-driver を使い続ける場合は `pmw3610-alt` compatible を使用。

## Technical Context

### Files Modified

**build.py**:
- Docker イメージを `zmkfirmware/zmk-dev-arm:4.1` に変更

**全キーボードの build.yaml**:
- `board: seeeduino_xiao_ble` → `board: xiao_ble`

**fish_dongle.conf / fish_dongle.overlay**:
- NFC ピン設定を DeviceTree に移行
- PMW3610 → PMW3610_ALT に変更

**taiyaki.conf / taiyaki.overlay**:
- NFC ピン設定を DeviceTree に移行

**s3kb, d3kb2 の .conf / .overlay ファイル**:
- 設定変更済みだがビルド不可

### Breaking Changes 発見リスト

| 変更内容 | Before | After |
|---------|--------|-------|
| Docker イメージ | zmk-dev-arm:3.5 | zmk-dev-arm:4.1 |
| ボード名 | seeeduino_xiao_ble | xiao_ble |
| NFC ピン設定 | `CONFIG_NFCT_PINS_AS_GPIOS=y` | `&uicr { nfct-pins-as-gpios; };` |
| PMW3610 compatible | pixart,pmw3610 | pixart,pmw3610-alt |
| PMW3610 Kconfig | CONFIG_PMW3610_* | CONFIG_PMW3610_ALT_* |
| マウス機能 | CONFIG_ZMK_MOUSE | CONFIG_ZMK_POINTING |

## Blockers & Issues

### Active Blockers

- **zmk-input-behavior-listener 非互換**: Zephyr 4.1 の `INPUT_CALLBACK_DEFINE` マクロ引数変更により s3kb と d3kb2 がビルド不可。モジュール作者（badjeff）による対応が必要。

### Known Issues

- **サイレント失敗**: Kconfig オプション名を間違えてもビルドは成功するが、設定が無視されて実行時に問題が発生する（例: マウスの動作がおかしい）

## Next Steps

1. [ ] badjeff/zmk-input-behavior-listener の Zephyr 4.1 対応を待つ
2. [ ] 対応後、s3kb と d3kb2 のビルド検証を実施
3. [ ] 変更を git commit してリモートにプッシュ

## Questions for Next Session

- [ ] badjeff/zmk-input-behavior-listener の Zephyr 4.1 対応状況は？
- [ ] s3kb と d3kb2 は Zephyr 3.5 のままでも良いか、フォークして自前対応すべきか？

## References

- [ZMK Zephyr 4.1 Blog Post](https://zmk.dev/blog/2025/12/09/zephyr-4-1)
- [badjeff/zmk-pmw3610-driver](https://github.com/badjeff/zmk-pmw3610-driver)
- [badjeff/zmk-input-behavior-listener](https://github.com/badjeff/zmk-input-behavior-listener)
- How-To: `context_doc/howto/20260206-0530-zmk-zephyr-4-1-migration.md`

## Environment State

- **Branch**: main
- **Last Commit**: 変更未コミット
- **Build Status**: d3kb, taiyaki, fish は成功 / s3kb, d3kb2 はスキップ
