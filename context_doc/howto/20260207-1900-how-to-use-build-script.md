# How-To: ビルドスクリプトの使い方 (build.zsh)

## Problem

ZMK キーボードファームウェアをローカルでビルドしたい。キーマップ変更後のファームウェアビルド、新しいキーボードの初期セットアップ、複数キーボードの一括ビルドなど、様々なビルドシナリオに対応する必要がある。

## Solution

`build.zsh` は Docker コンテナ内で west (Zephyr のビルドツール) を実行し、`.uf2` ファームウェアファイルを生成する。fzf によるインタラクティブ選択にも対応。

### 前提条件

- Docker が起動していること
- `yq` (Mike Farah 版) がインストール済みであること
- `fzf` がインストール済みであること（インタラクティブ選択を使う場合）

## Example

### 基本的なビルド（最も頻繁に使うコマンド）

```bash
./build.zsh keyboards/zmk-config-fish/build.yaml -p
```

`-p` (pristine) は前回のビルドキャッシュをクリアしてクリーンビルドを行う。キーマップ変更後は基本的にこれを使う。

### 新しいキーボードの初回セットアップ

```bash
./build.zsh --init keyboards/zmk-config-d3kb2/build.yaml
```

`--init` は以下を自動実行する:
1. 新しい Docker コンテナを作成
2. west ワークスペースを初期化 (`west init`)
3. ZMK ソースコードを取得 (`west update`)
4. ファームウェアをビルド

### ZMK ソースの更新

```bash
./build.zsh --update keyboards/zmk-config-fish/build.yaml
```

`west.yml` のリビジョンを変更した後に使う。`west update` で依存関係を再取得してからビルドを実行する。

### インタラクティブ選択（fzf）

```bash
./build.zsh
```

引数なしで実行すると fzf が起動し、`keyboards/*/build.yaml` から対象キーボードを選択できる。Tab で複数選択可能。右側にシールド名のプレビューが表示される。

### 複数キーボードの一括ビルド

```bash
./build.zsh keyboards/zmk-config-fish/build.yaml keyboards/zmk-config-d3kb2/build.yaml -p
```

### ヘルプの表示

```bash
./build.zsh --help
```

## When to Use

- キーマップや `.conf` を変更した後 → `./build.zsh <yaml> -p`
- 新しいキーボード設定を追加した後 → `./build.zsh --init <yaml>`
- `west.yml` の ZMK バージョンを更新した後 → `./build.zsh --update <yaml>`
- どのキーボードをビルドするか迷ったとき → `./build.zsh` (fzf)

## When NOT to Use

- GitHub Actions でビルドする場合（`build.yaml` はそのまま GA でも使用可能）
- Docker が起動していない環境

## Notes

- 出力 `.uf2` ファイルは `zmk_work/<keyboard-name>/` に配置される
- Docker コンテナはキーボード名ごとに作成・再利用される（毎回作り直さない）
- `--init` は既存のワークスペースを完全に削除して再作成する（注意）
- `build.yaml` の `artifact-name` フィールドで出力ファイル名をカスタマイズ可能
- `cp -rT` (GNU coreutils) を使用しているため macOS では動作しない
- 旧スクリプト `build.py` も残っている（Python + docker SDK + pyyaml が必要）

## References

- [ADR: ビルドスクリプトを Python から zsh に移行する](../adr/20260207-1900-build-script-python-to-zsh-migration.md)
- [Design: ZMK コードベースの取得・配置フロー](../design/20260207-1745-zmk-codebase-acquisition-flow.md)
- [Runbook: ZMK ファームウェアのビルド方法](../runbook/20260203-0000-zmk-firmware-build.md) (旧 build.py 版)
