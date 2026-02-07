# Design Document: ローカルモジュールオーバーライド機構

## Overview

ZMK ビルドシステムにローカルモジュールオーバーライド機構を追加する。`zmk_modules/` ディレクトリに配置したモジュールが `EXTRA_ZEPHYR_MODULES` CMake 変数を通じて自動的にビルドに組み込まれ、west.yml のリモートモジュールを push なしでオーバーライドできる。

## Goals

- ローカルに配置したZephyrモジュールをビルド時に自動検出し、`EXTRA_ZEPHYR_MODULES` 経由でビルドに注入する
- 既存の west.yml やCI/CD ワークフローに影響を与えない
- 新規モジュール開発・既存モジュール修正の両方に対応する
- Dockerコンテナのライフサイクルを自動管理し、マウント不整合を検出・修復する

## Non-Goals

- west.yml の自動書き換えや同期
- モジュールのバージョン管理・依存関係解決
- `EXTRA_ZEPHYR_MODULES` と同名の west マニフェストモジュールの競合検出（Zephyr 側の動作に依存）

## Background

ZMK モジュール（ドライバ、ビヘイビア等）は `west.yml` にリモート Git URL で記載される。開発中のモジュールを検証するにはコミット＆プッシュが必要で、イテレーションが遅い。Zephyr のビルドシステムには `EXTRA_ZEPHYR_MODULES` という CMake 変数があり、west マニフェスト外のモジュールを追加注入できる。これを活用してローカルのモジュールディレクトリを直接参照する。

## Requirements

### Functional Requirements

1. `zmk_modules/` 内の有効なモジュール（`zephyr/module.yml` を含むディレクトリ）を自動検出する
2. 検出されたモジュールのパスを `-DEXTRA_ZEPHYR_MODULES` として west build コマンドに渡す
3. `zmk_modules/` が存在しない場合、既存のビルド動作に一切影響しない
4. Docker コンテナに `zmk_modules/` を読み取り専用でマウントする
5. 既存コンテナにマウントがない場合、自動的に再作成する

### Non-Functional Requirements

1. **安全性**: コンテナ内からローカルモジュールを変更できない（`:ro` マウント）
2. **互換性**: CI/GitHub Actions での build.yaml ベースのビルドに影響しない
3. **パフォーマンス**: モジュール検出はキーボードごとに1回のみ実行（ターゲットごとではない）

## Design

### Architecture

```
ホストマシン
├── zmk_modules/                      ← ユーザーが配置
│   ├── my-new-driver/
│   │   └── zephyr/module.yml
│   └── zmk-pmw3610-driver/          ← 既存モジュールの上書き
│       └── zephyr/module.yml
│
├── build.sh
│   ├── detect_local_modules()        ← zmk_modules/ をスキャン
│   ├── container_ensure()            ← マウント検証 + コンテナ作成
│   └── build_target()                ← -DEXTRA_ZEPHYR_MODULES を注入
│
└── Docker コンテナ
    ├── -v zmk_work/kb/:zmk_work/kb/      (rw)
    └── -v zmk_modules/:zmk_modules/:ro   (ro, 条件付き)
```

### Components

#### Component 1: `detect_local_modules()`

- **Purpose**: `zmk_modules/` ディレクトリをスキャンし、有効なモジュールのパスリストを返す
- **Responsibilities**:
  - `zmk_modules/` が存在しない場合は何もしない（return 0）
  - 各サブディレクトリの `zephyr/module.yml` 存在をチェック
  - 有効なモジュールをログ出力
  - セミコロン区切りの絶対パス文字列を stdout に出力
- **Interfaces**: 引数なし → stdout にセミコロン区切りパス（CMake リスト形式）

#### Component 2: `container_ensure()` マウント検証

- **Purpose**: 既存コンテナの `zmk_modules` マウント有無を検証し、不整合を自動修復する
- **Responsibilities**:
  - `docker inspect` でコンテナのマウント情報を取得
  - `zmk_modules/` が存在するがマウントされていない場合、コンテナを再作成
  - 再帰ガード（`_recurse` パラメータ）で無限ループを防止
- **Interfaces**: 既存の `container_ensure(name, mount, force_new)` に `_recurse` パラメータを追加（内部使用のみ）

#### Component 3: コンテナ作成のマウント拡張

- **Purpose**: 新規コンテナ作成時に `zmk_modules/` を条件付きでマウントする
- **Responsibilities**:
  - `zmk_modules/` が存在する場合のみ `-v` フラグを追加
  - `:ro` フラグで読み取り専用を強制
- **Interfaces**: Docker ボリュームマウント引数の動的構築

#### Component 4: `build_target()` CMake 変数注入

- **Purpose**: ビルドコマンドに `EXTRA_ZEPHYR_MODULES` を追加する
- **Responsibilities**:
  - `detect_local_modules()` の結果を受け取り、空でなければ CMake 引数に追加
  - シェル経由で `sh -c` に渡されるため、セミコロンをシングルクォートで保護
- **Interfaces**: `build_target()` に `extra_modules` パラメータ追加（7番目の引数）

### Data Model

**モジュール検出の判定基準:**

```
zmk_modules/<name>/zephyr/module.yml が存在する → 有効なモジュール
zmk_modules/<name>/zephyr/module.yml が存在しない → スキップ（警告なし）
zmk_modules/ が存在しない → 機能全体がスキップ
```

**CMake への受け渡し形式:**

```
-DEXTRA_ZEPHYR_MODULES=/abs/path/mod1;/abs/path/mod2
```

セミコロンは CMake のリスト区切り文字であり、`sh -c` でコマンド区切りと解釈されないようシングルクォートで保護する。

### Error Handling

| シナリオ | 動作 |
|----------|------|
| `zmk_modules/` が存在しない | 無視（既存動作維持） |
| モジュールに `zephyr/module.yml` がない | スキップ（ログなし） |
| コンテナにマウントがない | 自動再作成（1回のみ） |
| コンテナ再作成に失敗 | 再帰ガードで通常フローに戻る |

## Implementation Plan

### Phase 1: 実装完了

- [x] `ZMK_MODULES_DIR` 定数を追加
- [x] `detect_local_modules()` 関数を実装
- [x] `container_ensure()` のマウント検証ロジックを実装
- [x] `container_ensure()` のコンテナ作成に条件付きマウントを追加
- [x] `build_target()` に `EXTRA_ZEPHYR_MODULES` 注入を追加
- [x] `.gitignore` に `zmk_modules` を追加

### Phase 2: 検証（未実施）

- [ ] `zmk_modules/` なしでビルド → 既存動作に変化なし
- [ ] テストモジュールを配置してビルド → ログに検出メッセージ表示
- [ ] 既存コンテナ + `zmk_modules/` 追加 → コンテナ自動再作成
- [ ] 同名モジュールのオーバーライド動作確認

## Testing Strategy

- **手動テスト (Phase 2)**: 実際のキーボードビルドで検証。`zmk_modules/` の有無でビルド動作を比較
- **シェルスクリプト構文チェック**: `bash -n build.sh` および `zsh -n build.sh` で構文エラーがないことを確認済み

## Security Considerations

- **`:ro` マウント**: コンテナ内プロセスがローカルモジュールのソースコードを変更できない
- **`.gitignore`**: `zmk_modules/` が誤ってコミットされることを防止
- **パス注入**: モジュールパスは `zmk_modules/` 直下のディレクトリのみ参照。ユーザー入力は介在しない

## Dependencies

- Zephyr ビルドシステムの `EXTRA_ZEPHYR_MODULES` CMake 変数サポート
- Docker のボリュームマウント機能
- `docker inspect` コマンドの JSON 出力形式

## Open Questions

- [ ] `EXTRA_ZEPHYR_MODULES` で同名モジュールが west マニフェスト版を確実にオーバーライドするか（Zephyr の `zephyr_module.cmake` の実装依存）
- [ ] 同名モジュールのオーバーライドが効かない場合、`west config manifest.project-filter` で特定モジュールを無効化する代替アプローチを検討

## References

- [ZMK コードベースの取得・配置フロー](../design/20260207-1745-zmk-codebase-acquisition-flow.md)
- [キーボード毎に独立したコードベースを使用](../adr/20260203-0000-keyboard-specific-codebase.md)
- [ビルドスクリプトを Python から zsh に移行する](../adr/20260207-1900-build-script-python-to-zsh-migration.md)
- [Zephyr Module Documentation](https://docs.zephyrproject.org/latest/develop/modules.html)
