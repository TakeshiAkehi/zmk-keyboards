# Design Document: ZMK モジュール統合の二重メカニズム

## Overview

ZMK ビルドシステムには、ローカル開発とCI/CD環境で異なるモジュール統合メカニズムが存在する。ローカルビルドでは `zmk_modules/` ディレクトリから追加モジュールを注入し、CI（GitHub Actions）では各キーボード設定リポジトリ自体を Zephyr モジュールとして扱う。この設計文書は、両メカニズムの実装・目的・相互関係を明確化し、サブモジュールに変更を加えずにローカルモジュール開発を行う現在の構成が最適である理由を示す。

## Goals

- ローカルビルドとCI環境におけるモジュール統合の違いを明確化する
- 各メカニズムの目的と適用範囲を文書化する
- サブモジュール（キーボード設定リポジトリ）に変更を加えない設計方針の根拠を示す
- 開発者がローカルでモジュール開発する際のベストプラクティスを提供する

## Non-Goals

- 両メカニズムの統一（意図的に分離されている）
- キーボード設定リポジトリの構造変更
- west.yml によるリモートモジュール管理の詳細

## Background

ZMK キーボードファームウェアは Zephyr RTOS 上で動作し、カスタムドライバー・behavior・ボード定義などを「モジュール」として拡張できる。本リポジトリは複数のキーボード設定を git submodule として管理しており、各キーボードは独立した ZMK 設定リポジトリ（[unified-zmk-config-template](https://github.com/zmkfirmware/unified-zmk-config-template) ベース）である。

上流の ZMK CI ワークフロー（`zmkfirmware/zmk/.github/workflows/build-user-config.yml`）は単一キーボード設定リポジトリを前提としており、そのリポジトリ自体を Zephyr モジュールとして `-DZMK_EXTRA_MODULES` 経由でビルドに組み込む。一方、本リポジトリのローカルビルドシステムは複数キーボードのマルチリポジトリ構成に対応するため、別のアプローチを採用している。

## Design

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ ローカルビルド環境 (act + build-local.yml)                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  リポジトリルート/                                          │
│  ├── zmk_modules/                 ← 追加モジュール配置       │
│  │   └── my-driver/                                        │
│  │       ├── CMakeLists.txt                                │
│  │       ├── Kconfig                                       │
│  │       ├── src/                                          │
│  │       └── zephyr/module.yml                             │
│  │                                                          │
│  ├── keyboards/                   ← キーボード設定（変更なし）│
│  │   └── zmk-config-xxx/          (git submodule)          │
│  │       ├── boards/shields/xxx/   ← シールド定義           │
│  │       ├── config/west.yml       ← ZMK バージョン指定     │
│  │       └── zephyr/module.yml     ← board_root 宣言のみ    │
│  │                                                          │
│  └── zmk_work/zmk-config-xxx/zmk/  ← ビルドワークスペース    │
│      ├── config/                   (boards/ をコピー)       │
│      │   └── boards/shields/xxx/                           │
│      ├── zmk/                      (west clone)            │
│      └── zephyr/                   (west clone)            │
│                                                             │
│  【モジュール注入メカニズム】                                  │
│  1. zmk_modules/ 自動検出                                   │
│     → build-local.yml: Detect Local Modules ステップ        │
│  2. -DEXTRA_ZEPHYR_MODULES="/repo/zmk_modules/my-driver"   │
│  3. -DZMK_CONFIG="/workdir/config"  (boards/ 検出用)        │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ CI 環境 (GitHub Actions)                                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  zmk-config-xxx/ (リポジトリルート)                          │
│  ├── boards/shields/xxx/          ← シールド定義            │
│  ├── config/west.yml              ← ZMK + リモートモジュール │
│  └── zephyr/module.yml            ← モジュール宣言          │
│      build:                                                 │
│        settings:                                            │
│          board_root: .            ← boards/ を検出可能に     │
│                                                             │
│  【モジュール注入メカニズム】                                  │
│  1. zephyr/module.yml 存在チェック                          │
│     → build-user-config.yml: Prepare variables ステップ     │
│  2. -DZMK_EXTRA_MODULES="${GITHUB_WORKSPACE}"               │
│     (リポジトリ全体をモジュールとして追加)                   │
│  3. 分離ディレクトリで config/ をコピー                       │
│     → /tmp/zmk-config/ に隔離                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Component 1: ローカルビルド — zmk_modules/ ベースモジュール注入

#### Purpose

開発者がローカルでカスタムモジュール（ドライバー・behavior等）を作成・テストする際、コミット＆プッシュなしで即座にビルドに反映させる。

#### Implementation

**ファイル**: `.github/workflows/build-local.yml` (lines 91-106)

```yaml
- name: Detect Local Modules
  id: modules
  if: contains(inputs.phase, 'build')
  run: |
    extra=""
    if [ -d "${{ env.ZMK_MODULES_DIR }}" ]; then
      for d in "${{ env.ZMK_MODULES_DIR }}"/*/; do
        [ -d "$d" ] || continue
        if [ -f "${d}zephyr/module.yml" ]; then
          d="${d%/}"
          extra="${extra:+${extra};}${d}"
          echo "local module: ${d##*/}"
        fi
      done
    fi
    echo "extra_modules=${extra}" >> "$GITHUB_OUTPUT"
```

**環境変数**:
- `ZMK_MODULES_DIR: ${{ github.workspace }}/zmk_modules` (line 74)

**west build への注入** (line 122):
```yaml
${{ steps.modules.outputs.extra_modules != '' &&
    format('"-DEXTRA_ZEPHYR_MODULES={0}"', steps.modules.outputs.extra_modules) || '' }}
```

#### Responsibilities

1. `zmk_modules/` ディレクトリをスキャン
2. `zephyr/module.yml` を持つサブディレクトリを検出
3. セミコロン区切りの絶対パス文字列を生成（CMake リスト形式）
4. `-DEXTRA_ZEPHYR_MODULES` として west build に渡す

#### Module Requirements

モジュールとして認識されるための条件:
```
zmk_modules/<module-name>/
└── zephyr/module.yml    # 必須ファイル

# module.yml の例（ドライバーモジュール）
build:
  cmake: .
  kconfig: Kconfig
  settings:
    dts_root: .
```

#### Key Design Decisions

| 決定 | 理由 |
|------|------|
| リポジトリルートに配置 | 全キーボードで共有可能。キーボード設定の変更不要 |
| gitignore | コミット防止。開発中のコードの誤プッシュを回避 |
| 自動検出 | 明示的な設定不要。モジュール配置だけで有効化 |
| act --bind でマウント | ホストのファイルシステムをそのまま利用。永続化不要 |

### Component 2: CI ビルド — キーボード設定リポジトリのモジュール化

#### Purpose

キーボード設定リポジトリが持つカスタムボード/シールド定義を Zephyr のモジュールシステム経由で検出可能にする。

#### Implementation

**ファイル**: 上流 `zmkfirmware/zmk/.github/workflows/build-user-config.yml` (lines 75-82)

```yaml
- name: Prepare variables
  run: |
    if [ -e zephyr/module.yml ]; then
      export zmk_load_arg=" -DZMK_EXTRA_MODULES='${GITHUB_WORKSPACE}'"
      new_tmp_dir="${TMPDIR:-/tmp}/zmk-config"
      mkdir -p "${new_tmp_dir}"
      echo "base_dir=${new_tmp_dir}" >> $GITHUB_ENV
    else
      echo "base_dir=${GITHUB_WORKSPACE}" >> $GITHUB_ENV
    fi
```

**キーボード設定リポジトリの構造**:
```
zmk-config-xxx/
├── boards/shields/xxx/       # カスタムシールド定義
├── config/west.yml           # ZMK バージョン・依存モジュール
└── zephyr/module.yml         # モジュール宣言
    build:
      settings:
        board_root: .          # boards/ を検出可能に
```

#### Responsibilities

1. リポジトリルートの `zephyr/module.yml` 存在チェック
2. 存在する場合、`${GITHUB_WORKSPACE}` を `-DZMK_EXTRA_MODULES` に追加
3. 分離ディレクトリ (`/tmp/zmk-config/`) で config ファイルをコピー
4. Zephyr のモジュールシステムが `board_root: .` を解釈し、`boards/` をスキャン

#### Module.yml の役割

`board_root: .` の設定により、Zephyr ビルドシステムは以下を認識:
- `boards/arm/` — カスタムボード定義
- `boards/shields/` — カスタムシールド定義

**重要**: `board_root` のみの場合、ドライバーやbehavior等のソースコードは含まれない。これらを追加するには `cmake`, `kconfig`, `dts_root` の設定も必要。

### Component 3: boards/ 配置の違い

#### ローカルビルド

**配置先**: `zmk_work/<keyboard>/zmk/config/boards/`

**メカニズム**:
1. `build.sh` が `keyboards/zmk-config-xxx/boards/` をホスト側でコピー (line 407)
   ```bash
   cp -rT "$boardsdir" "$wboardsdir"
   ```
2. `-DZMK_CONFIG="${{ env.CONFDIR }}"` で ZMK に config ディレクトリを通知 (build-local.yml line 121)
3. ZMK が `${ZMK_CONFIG}/boards/` を自動スキャン

**利点**:
- キーボード設定リポジトリに `zephyr/module.yml` の変更不要
- 複数キーボードのサブモジュール構成に対応

#### CI ビルド

**配置先**: `${GITHUB_WORKSPACE}/boards/` （リポジトリルート直下）

**メカニズム**:
1. `zephyr/module.yml` の `board_root: .` により Zephyr が自動検出
2. `-DZMK_EXTRA_MODULES='${GITHUB_WORKSPACE}'` でリポジトリ全体をモジュール化
3. Zephyr のモジュールシステムが `boards/` をスキャン

**利点**:
- 上流の ZMK ワークフローと互換性
- シンプルな1リポジトリ=1キーボード構成

## Design Rationale: なぜ二重メカニズムか

### 問題: 構成の不一致

| 項目 | 上流 CI の前提 | 本リポジトリの構成 |
|------|--------------|------------------|
| リポジトリ構造 | 1リポジトリ = 1キーボード | 1リポジトリ = N キーボード（submodule） |
| ワークスペース | `${GITHUB_WORKSPACE}` = config repo root | `zmk_work/<keyboard>/zmk/` |
| boards/ の位置 | リポジトリルート直下 | config/ 内にコピー |
| モジュール追加 | config repo 自体をモジュール化 | zmk_modules/ で別途管理 |

### 解決策: 環境別最適化

#### CI 環境
- **制約**: 上流ワークフロー (`build-user-config.yml`) を変更不可
- **対応**: キーボード設定リポジトリの `zephyr/module.yml` で `board_root: .` を宣言
- **結果**: boards/ が Zephyr モジュールシステム経由で検出される

#### ローカル環境
- **制約**: 複数キーボードをサブモジュールで管理。act は reusable workflow 非対応
- **対応**: build-local.yml をインライン実装。`-DZMK_CONFIG` で boards/ 検出
- **結果**: zmk_modules/ で追加モジュールを柔軟に管理

### サブモジュール変更を避ける理由

#### 理由 1: CI/CD との互換性維持

キーボード設定リポジトリ（`keyboards/zmk-config-xxx/`）は独立したプロジェクトであり、それぞれが上流の ZMK CI ワークフローで動作している。`zephyr/module.yml` の構造を変更（例: `cmake: .`, `kconfig: Kconfig` を追加）すると、CI での動作に影響する可能性がある。

#### 理由 2: 関心の分離

| モジュールの種類 | 配置場所 | 管理単位 |
|----------------|---------|---------|
| **ボード/シールド定義** | `keyboards/*/boards/` | キーボード固有（submodule） |
| **開発中のドライバー・behavior** | `zmk_modules/` | リポジトリ共通（gitignore） |
| **確定したリモートモジュール** | `config/west.yml` | キーボード固有（submodule） |

`zmk_modules/` は**ローカル開発専用の一時的な領域**として明確に分離されている。これにより:
- 開発中のコードがサブモジュールに混入しない
- 全キーボードで共有可能なモジュールを1箇所で管理
- サブモジュールの独立性・再利用性を維持

#### 理由 3: 上流テンプレートとの一致

`keyboards/zmk-config-xxx/` は [unified-zmk-config-template](https://github.com/zmkfirmware/unified-zmk-config-template) から fork されている。テンプレートの構造を維持することで:
- 上流の改善を容易に取り込める
- 他の ZMK ユーザーとの互換性
- ドキュメント・サンプルコードの再利用性

## Data Flow Comparison

### ローカルビルド

```
1. build.sh が build.yaml をパース
2. keyboards/zmk-config-xxx/boards/ → zmk_work/xxx/zmk/config/boards/ にコピー
3. act が build-local.yml を実行
   ├── zmk_modules/ をスキャン → EXTRA_ZEPHYR_MODULES に追加
   └── west build -DZMK_CONFIG=config/ -DEXTRA_ZEPHYR_MODULES=zmk_modules/my-driver
4. ZMK が config/boards/ をスキャン（-DZMK_CONFIG 経由）
5. Zephyr が zmk_modules/my-driver をロード（-DEXTRA_ZEPHYR_MODULES 経由）
```

### CI ビルド

```
1. GitHub Actions が build.yml をトリガー
2. zmkfirmware/zmk/.github/workflows/build-user-config.yml を呼び出し
3. zephyr/module.yml 存在チェック → 存在する
   ├── config/ を /tmp/zmk-config/ にコピー
   └── west build -DZMK_EXTRA_MODULES="${GITHUB_WORKSPACE}"
4. Zephyr が ${GITHUB_WORKSPACE}/boards/ をスキャン（board_root: . 経由）
5. west.yml の projects で指定されたリモートモジュールをクローン・ロード
```

## Module Development Workflow

### シナリオ 1: カスタムドライバー開発

**要件**: PMW3610 センサードライバーを修正してテストしたい

**手順**:
```bash
# 1. zmk_modules/ にドライバーを配置
mkdir -p zmk_modules/zmk-pmw3610-driver
cd zmk_modules/zmk-pmw3610-driver

# 2. リモートからクローン or 手動で作成
git clone https://github.com/badjeff/zmk-pmw3610-driver .

# 3. ドライバーのコードを修正
vim src/pmw3610.c

# 4. ビルド（自動検出される）
cd /path/to/repo
./build.sh keyboards/zmk-config-fish/build.yaml

# 5. ビルドログで検出確認
# → "local module: zmk-pmw3610-driver"
```

**注意**: `zmk_modules/` 内の変更は gitignore されている。確定したらリモートリポジトリにプッシュし、`config/west.yml` の `projects` に追加する。

### シナリオ 2: カスタムシールド追加

**要件**: 新しいキーボードレイアウトを作成したい

**手順**:
```bash
# 1. キーボード設定リポジトリ内で作業
cd keyboards/zmk-config-xxx/boards/shields/

# 2. 新しいシールド定義を作成
mkdir my_new_shield
vim my_new_shield/my_new_shield.overlay
vim my_new_shield/my_new_shield.keymap
vim my_new_shield/Kconfig.shield

# 3. build.yaml に追加
vim ../../build.yaml

# 4. ビルド
cd /path/to/repo
./build.sh keyboards/zmk-config-xxx/build.yaml
```

**理由**: シールド定義はキーボード固有のためサブモジュール内で管理。`zmk_modules/` は不要。

### シナリオ 3: 既存モジュールのローカルオーバーライド

**要件**: west.yml で参照しているリモートモジュールをローカルで修正したい

**手順**:
```bash
# 1. zmk_modules/ にクローン
cd zmk_modules
git clone https://github.com/zmkfirmware/zmk-some-module

# 2. 修正
cd zmk-some-module
vim src/driver.c

# 3. ビルド（zmk_modules/ の方が優先される）
cd /path/to/repo
./build.sh keyboards/zmk-config-xxx/build.yaml
```

**動作**: Zephyr の `EXTRA_ZEPHYR_MODULES` が west.yml のモジュールより優先されるため、ローカル版が使用される。

## Error Handling

### ケース 1: zmk_modules/ にモジュールがあるが module.yml がない

**動作**: スキップ（ログ出力なし）

**理由**: ディレクトリの存在だけでモジュールと判定せず、明示的な `zephyr/module.yml` を要求

### ケース 2: CI で zephyr/module.yml がない場合

**動作**: `base_dir=${GITHUB_WORKSPACE}` を設定し、通常のビルドフローを実行

**理由**: モジュール化はオプション。古い設定リポジトリとの後方互換性

### ケース 3: ローカルとリモートで同名モジュールが存在

**動作**: Zephyr の CMake ロジックに依存（通常は EXTRA_ZEPHYR_MODULES が優先）

**警告**: 公式にサポートされた動作ではないため、明示的なテストが必要

## Performance Considerations

### ローカルビルド

- **モジュール検出**: O(N) スキャン。N = zmk_modules/ 内のディレクトリ数
- **act 起動**: 約 3-5秒/ターゲット（コンテナ起動オーバーヘッド）
- **west build**: 約 15-30秒（pristine build）、5-10秒（incremental）

### CI ビルド

- **モジュール検出**: 単一の `[ -e zephyr/module.yml ]` チェック（O(1)）
- **GitHub Actions 起動**: 約 30-60秒（ランナーの初期化）
- **west build**: ローカルと同等

## Security Considerations

### zmk_modules/ の隔離

- **gitignore**: 開発中のコードが誤ってコミットされることを防止
- **read-only mount** (Docker 時代の名残。act --bind は rw だが、コンテナの一時性により安全)
- **act の一時性**: コンテナはビルド後に削除されるため、状態が永続化されない

### サブモジュールの保護

- `build.sh` はサブモジュール内のファイルを変更しない（read-only コピーのみ）
- zmk_modules/ とサブモジュールが物理的に分離されている

## Future Considerations

### 統一の可能性

act が reusable workflow をサポートした場合（[issue #826](https://github.com/nektos/act/issues/826)）、ローカルでも上流の `build-user-config.yml` を直接呼び出せる可能性がある。ただし、複数キーボードのマルチリポジトリ構成は引き続き独自対応が必要。

### モジュール管理の改善

- `zmk_modules/` 内のモジュールバージョン管理（git submodule 化の検討）
- ローカルモジュールと west.yml モジュールの競合検出ツール

## References

- [ADR: ビルドシステムを Docker 直接管理から act ベースに移行する](20260215-adr-build-system-docker-to-act-migration.md)
- [Design: ローカルモジュールオーバーライド機構](20260207-design-local-module-override.md)
- [Design: ZMK コードベースの取得・配置フロー](20260207-design-zmk-codebase-acquisition-flow.md)
- [ZMK build-user-config.yml (upstream)](https://github.com/zmkfirmware/zmk/blob/main/.github/workflows/build-user-config.yml)
- [Zephyr Module Documentation](https://docs.zephyrproject.org/latest/develop/modules.html)
- [unified-zmk-config-template](https://github.com/zmkfirmware/unified-zmk-config-template)
