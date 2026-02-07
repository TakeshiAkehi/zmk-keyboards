# ADR: ビルドスクリプトを Python から zsh に移行する

## Status

Proposed

## Context

現在の ZMK ファームウェアビルドスクリプト `build.py` は Python で実装されており、`docker` Python SDK と `pyyaml` を使用して Docker コンテナの管理と build.yaml のパースを行っている。ビルド対象のキーボード・ターゲットは CLI 引数で手動指定する必要があり、日常的なビルド作業のUXに改善の余地がある。

fzf によるインタラクティブなビルドターゲット選択を実現したいが、Python からの fzf 呼び出しは `subprocess` 経由となり、パイプやプロセス置換を多用する fzf のエコシステムとの親和性が低い。

## Decision

ビルドスクリプトを Python (`build.py`) から zsh スクリプトに書き換える。主な変更点:

- Docker 操作: Python SDK → `docker` CLI 直接呼び出し
- YAML パース: `pyyaml` → `yq` コマンド
- 引数解析: `argparse` → `zparseopts`
- ファイル操作: `shutil` / `pathlib` → `cp -r`, `mkdir -p`, zsh パス展開
- **新機能**: fzf によるキーボード・ビルドターゲットのインタラクティブ選択

## Consequences

### Positive

- fzf によるインタラクティブ選択が自然に統合でき、ビルド対象の選択 UX が大幅に向上する
- Docker CLI 直接呼び出しにより、Python SDK のラッパーコードが不要になりシンプルになる
- `.venv` 環境や `docker`/`pyyaml` パッケージへの依存がなくなる
- `./build.zsh` の直接実行が可能になり起動が速くなる

### Negative

- エラーハンドリングの表現力が Python の `try/except` と比較して低下する
- YAML パースが `yq` 依存になる（ただし build.yaml の構造は固定的なので実用上問題なし）
- Python に慣れている場合、zsh スクリプトの保守性がやや低く感じる可能性がある

### Risks

- **yq のバージョン差異**: `yq` には Mike Farah版と kislyuk版が存在し、構文が異なる。使用するバージョンを明示し、スクリプト内でバージョンチェックを行うことで軽減する
- **Docker コンテナ状態管理の複雑さ**: 現在の3分岐ロジック（存在→再利用 / なし→新規 / exited→再起動）を `docker inspect` ベースで再実装する必要がある。テストケースを整備して確認する

## Alternatives Considered

### Alternative 1: Python に fzf を組み込む

- **Pros**: 既存コードの大部分を維持できる。エラーハンドリングが堅牢
- **Cons**: `subprocess.run(['fzf', ...])` 経由の呼び出しとなり、`--preview` でのシェルコマンド連携やパイプが不自然。Python とシェルの世界を行き来する中途半端な構成になる
- **Why rejected**: fzf 統合が主目的であり、シェルスクリプトのほうが自然に統合できるため

### Alternative 2: Python + `iterfzf` ライブラリ

- **Pros**: Python のまま fzf ライクな選択 UI を実現できる
- **Cons**: `iterfzf` は fzf のフル機能（`--preview`, `--multi`, `--bind` 等）をサポートしていない。追加の依存関係が増える
- **Why rejected**: fzf のフル機能を活用したインタラクティブ体験を実現するには不十分

### Alternative 3: bash で書く

- **Pros**: Linux でデフォルトで利用可能。zsh より広い互換性
- **Cons**: 連想配列やパス操作の機能が zsh より貧弱。`zparseopts` に相当する引数解析が煩雑
- **Why rejected**: 個人用途のリポジトリであり、開発環境に zsh がインストール済み。zsh の方が表現力が高い

## References

- `build.py` - 現在のビルドスクリプト（約250行）
- `context_doc/design/20260207-1745-zmk-codebase-acquisition-flow.md` - ZMK コードベース取得フローの設計書
- `context_doc/adr/20260203-0000-keyboard-specific-codebase.md` - キーボード毎の独立コードベース方針
- `context_doc/runbook/20260203-0000-zmk-firmware-build.md` - 現行ビルド手順書（Python ベース）
