# Handoff: ZMK Zephyr 3.5 → 4.1 マイグレーション

## メタデータ
- **作成日**: 2026-02-05
- **ステータス**: 作業中（ビルド検証待ち）
- **担当**: Claude Code セッション

## 概要

ZMKがZephyr 4.1ベースに移行したことに伴い、このリポジトリの全キーボード設定をZephyr 4.1対応に更新する作業。

参考: https://zmk.dev/blog/2025/12/09/zephyr-4-1

## 完了した作業

### 1. build.py のDockerイメージ更新
- **ファイル**: `build.py:42`
- **変更**: `zmkfirmware/zmk-dev-arm:3.5` → `zmkfirmware/zmk-dev-arm:4.1`

### 2. NFC ピン設定の移行（6ファイル）

Zephyr 4.1では `CONFIG_NFCT_PINS_AS_GPIOS` Kconfigが非推奨。DeviceTreeに移行。

| キーボード | .conf から削除 | .overlay に追加 |
|-----------|---------------|----------------|
| fish_dongle | ✅ | ✅ `&uicr { nfct-pins-as-gpios; };` |
| s3kb_front | ✅ | ✅ |
| s3kb_back | ✅ | ✅ |
| d3kb2_left | ✅ | ✅ |
| d3kb2_right | ✅ | ✅ |
| taiyaki | ✅ | ✅ |

**注**: d3kb は元々この設定を使用していなかったため変更不要。

### 3. PMW3610ドライバーの更新（3キーボード）

Zephyr 4.1には上流のPMW3610ドライバーが含まれるため、badjeff版ドライバーとの競合を回避する必要がある。

| キーボード | .conf 変更 | .overlay 変更 |
|-----------|-----------|--------------|
| fish_dongle | `CONFIG_PMW3610=y` → `CONFIG_PMW3610_ALT=y` | `compatible = "pixart,pmw3610"` → `"pixart,pmw3610-alt"` |
| s3kb_back | 同上 | 同上 |
| s3kb_front | 同上 | （デバイスなし） |
| d3kb2_right | 同上 | 同上 |

## 未完了の作業

### ビルド検証

以下の順序でビルドを実行し、.uf2ファイルが生成されることを確認する：

```bash
# 1. 既存コンテナを削除
bash close_all_container.bash

# 2. ビルド実行（シンプルなものから）
python build.py keyboards/zmk-config-d3kb/build.yaml --init      # PMW3610なし
python build.py keyboards/zmk-config-taiyaki/build.yaml --init   # PMW3610なし
python build.py keyboards/zmk-config-fish/build.yaml --init      # PMW3610あり
python build.py keyboards/zmk-config-s3kb/build.yaml --init      # PMW3610あり
python build.py keyboards/zmk-config-d3kb2/build.yaml --init     # PMW3610あり

# 3. 成功確認
ls -la keyboards/*/zmk_work/*.uf2
```

### ファームウェア動作確認

ビルド成功後、ユーザーが別途実施予定。

## 変更ファイル一覧

```
build.py                                                          # Dockerイメージ
keyboards/zmk-config-fish/boards/shields/fish/fish_dongle.conf
keyboards/zmk-config-fish/boards/shields/fish/fish_dongle.overlay
keyboards/zmk-config-s3kb/boards/shields/s3kb/s3kb_front.conf
keyboards/zmk-config-s3kb/boards/shields/s3kb/s3kb_front.overlay
keyboards/zmk-config-s3kb/boards/shields/s3kb/s3kb_back.conf
keyboards/zmk-config-s3kb/boards/shields/s3kb/s3kb_back.overlay
keyboards/zmk-config-d3kb2/boards/shields/d3kb2/d3kb2_left.conf
keyboards/zmk-config-d3kb2/boards/shields/d3kb2/d3kb2_left.overlay
keyboards/zmk-config-d3kb2/boards/shields/d3kb2/d3kb2_right.conf
keyboards/zmk-config-d3kb2/boards/shields/d3kb2/d3kb2_right.overlay
keyboards/zmk-config-taiyaki/boards/shields/taiyaki/taiyaki.conf
keyboards/zmk-config-taiyaki/boards/shields/taiyaki/taiyaki.overlay
```

## 潜在的な問題

### 外部モジュールの互換性

以下のモジュールはZephyr 4.1での動作が未検証：

| モジュール | リポジトリ | 使用キーボード |
|-----------|-----------|---------------|
| zmk-pmw3610-driver | badjeff/zmk-pmw3610-driver | fish, s3kb, d3kb2 |
| zmk-mouse-gesture | kot149/zmk-mouse-gesture | fish |
| zmk-scroll-snap | kot149/zmk-scroll-snap | fish, s3kb |

ビルドエラーが発生した場合、これらのモジュールの互換性を調査する必要がある。

## 関連ドキュメント

- 詳細計画: `.claude/plans/floating-kindling-fern.md`
- 作業メモ: `plan.tmp.md`
- ADR-001: `context_doc/adr/20260203-0000-keyboard-specific-codebase.md`
