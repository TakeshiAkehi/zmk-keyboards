# ADR: act ベースビルドシステムから Docker 直接管理に回帰する

## Status

Accepted (2026-02-16 実装完了・テスト済み)

## Context

2026-02-15 に [ADR: ビルドシステムを Docker 直接管理から act ベースに移行する](20260215-adr-build-system-docker-to-act-migration.md) で決定した act ベースのビルドシステムは、CI/ローカルの統一という目標を掲げて導入された。しかし、運用1日で以下の問題が明らかになった。

### act 導入の当初目標と実態

**期待していたこと**:
- CI と完全に同じワークフロー定義 (`.github/workflows/build.yml`) を使用
- ローカルビルドと GitHub Actions のビルドロジックが一致

**実際の結果**:
- `build-local.yml` は上流の `build-user-config.yml` とは別実装（act の reusable workflow 制限により）
- CI/ローカルの「統一」は達成されず、むしろ2つのワークフロー定義を保守する必要が生じた

### パフォーマンス問題

act は各ターゲットごとに新しいコンテナを起動・破棄する設計のため、以下のオーバーヘッドが発生:

| キーボード | ターゲット数 | act オーバーヘッド | ビルド時間への影響 |
|-----------|------------|------------------|-------------------|
| s3kb | 2 | 6-10秒 (2コンテナ) | +10-20% |
| fish | 5 | 15-25秒 (5コンテナ) | +15-25% |

従来の Docker 直接管理では、同一キーボードの複数ターゲットは同じコンテナ内で連続ビルドできていたが、act ではこれが不可能。

### 統一の幻想

`.github/workflows/build-local.yml` は:
- act 専用に作成されたローカルビルド用ワークフロー
- 上流の `build-user-config.yml` とはロジックが異なる（マルチキーボード対応、zmk_modules/ 検出等）
- GitHub Actions では実行されない（ローカル専用）

つまり、**「CI/ローカルで同じワークフローを共有」という目標は達成されていない**。むしろ `build.sh` (bash) と `build-local.yml` (YAML) の2つの実装を保守する必要が生じた。

### 決定を覆す根拠

1. **統一のメリットが得られない**: `build-local.yml` は CI で使われないため、「同じ定義」の価値がない
2. **パフォーマンス劣化**: ターゲット数に比例したコンテナ起動オーバーヘッド
3. **実装の重複**: bash → YAML への移植だけで、本質的な改善がない
4. **act への不要な依存**: Docker だけで十分達成できることに追加ツールが必要

## Decision

Docker 直接管理に回帰し、**ターゲットのバッチ実行**により従来より高速なビルドを実現する。

### アーキテクチャ

```
build.sh (orchestrator - bash のみ)
  ├── parse build.yaml with yq (same as before)
  ├── fzf interactive selection (same as before)
  ├── Host-side:
  │   ├── cp config/, boards/ → zmk_work/
  │   └── detect_modules() — zmk_modules/ と keyboard module を検出
  └── For each keyboard (not per target):
      └── docker run --rm -v $REPO_ROOT:$REPO_ROOT bash -c "
            cd workdir
            west zephyr-export
            west build ... (target 1)
            west build ... (target 2)
            ...
         "
```

### 主な変更内容

#### 1. `build.sh` の変更

**削除するもの**:
- `act_run()` 関数
- `WORKFLOW_FILE` 定数
- act への依存チェック

**追加するもの**:
- `docker_run()` 関数: シンプルな `docker run --rm -v` ラッパー
- `detect_modules()` 関数: ホスト側でモジュール検出（`build-local.yml` から移植）

**変更する関数**:
```bash
builder_init:   rm workspace → cp config → docker_run("west init -l config")
builder_update: cp config → docker_run("west update")
builder_build:
  1. detect_modules() で zmk_modules/ と keyboard module を検出
  2. 全ターゲットを1つのシェルスクリプトに結合:
     - west zephyr-export (1回のみ)
     - west build (target 1)
     - west build (target 2)
     - ...
  3. docker_run() で一括実行
```

#### 2. モジュール検出のホスト側実行

`build-local.yml` のモジュール検出ロジック (lines 93-120) を `detect_modules()` bash 関数としてインライン化:

```bash
detect_modules() {
    local kb_config_dir="$1"
    local zmk_modules_dir="$REPO_ROOT/zmk_modules"
    local extra=""

    # zmk_modules/ スキャン
    if [[ -d "$zmk_modules_dir" ]]; then
        for d in "$zmk_modules_dir"/*/; do
            [[ -d "$d" ]] || continue
            if [[ -f "${d}zephyr/module.yml" ]]; then
                d="${d%/}"
                extra="${extra:+${extra};}${d}"
                log "  local module: ${d##*/}"
            fi
        done
    fi

    # keyboard config がモジュールか確認
    _kb_is_module=false
    if [[ -f "${kb_config_dir}/zephyr/module.yml" ]]; then
        extra="${extra:+${extra};}${kb_config_dir}"
        log "  keyboard config module: ${kb_config_dir##*/}"
        _kb_is_module=true
    fi

    _extra_modules="$extra"
}
```

#### 3. バッチビルドの実装

従来: ターゲットごとに `act_run()` → コンテナ起動
```bash
for target in targets; do
    act_run "$keyboard_name" "build" ... "$board" "$shield" ...
done
```

変更後: 全ターゲットを1つのスクリプトに結合 → 1回の `docker run`
```bash
script="set -e\ncd '$workdir'\nwest zephyr-export\n"
for target in targets; do
    script+="west build -s zmk/app -b '$board' -d '$builddir' -- $cmake_flags\n"
    script+="cp '$builddir/zephyr/zmk.uf2' '$workdir_top/${output_name}.uf2'\n"
done
docker_run "$(printf '%b' "$script")"
```

#### 4. `.github/workflows/build-local.yml` の非推奨化

- ファイルは削除せず保持（将来 GitHub Actions CI で使う可能性）
- ファイル冒頭に DEPRECATED コメント追加
- ローカルビルドでは使用されないことを明記

## Consequences

### Positive

1. **パフォーマンス向上**: ターゲット数に比例したコンテナ起動オーバーヘッドを削減
   - 2ターゲット: 3-5秒削減
   - 5ターゲット: 12-20秒削減
2. **実装のシンプル化**: bash のみで完結。YAML/act の知識不要
3. **依存の削減**: act が不要に。Docker のみで動作
4. **保守性向上**: ビルドロジックが1ファイル (`build.sh`) に集約
5. **west zephyr-export の最適化**: キーボードごとに1回のみ実行（従来はターゲットごと）

### Negative

1. **CI/ローカル分離の固定化**: `build.sh` と GitHub Actions ワークフローは完全に別実装
2. **ワークフロー定義の不使用**: `.github/workflows/build-local.yml` がローカルで使われなくなる

### Risks

**リスク**: Docker のバージョン互換性
- **軽減策**: Docker CLI の基本機能 (`run`, `-v`, `-w`) のみ使用。安定したインターフェース

**リスク**: モジュール検出ロジックの重複（bash と YAML で別実装の可能性）
- **軽減策**: `build-local.yml` は非推奨化し、bash 実装 (`detect_modules()`) を正とする

## Alternatives Considered

### Alternative 1: act を維持し、matrix strategy で最適化

- **Pros**: act の利用継続。ワークフロー定義を保持
- **Cons**: act の matrix は並列実行されず、シーケンシャル実行でオーバーヘッドは変わらず
- **Why rejected**: パフォーマンス問題が解決されない

### Alternative 2: 永続コンテナ管理（pre-act のアプローチ）

- **Pros**: コンテナ再利用で最速
- **Cons**: ライフサイクル管理の複雑さ（起動・停止・削除・状態管理）
- **Why rejected**: バッチ実行で十分な速度。複雑さに見合わない

### Alternative 3: GitHub Actions を直接ローカルで実行

- **Pros**: 完全な CI/ローカル統一
- **Cons**: act 以外に標準的な方法がない。Docker Compose 等でエミュレートするのは act より複雑
- **Why rejected**: act の問題点（オーバーヘッド、reusable workflow 非対応）は解決されない

## Implementation

### 実装済み (2026-02-16)

- [x] `build.sh` の変更（119行追加、45行削除）
  - `docker_run()` 関数追加
  - `detect_modules()` 関数追加（build-local.yml から移植）
  - `builder_init()`, `builder_update()` をシンプル化
  - `builder_build()` をバッチ実行に書き換え
  - `check_dependencies()` を docker チェックに変更
  - `show_help()` を "Docker containers" に更新
- [x] `.github/workflows/build-local.yml` に非推奨コメント追加
- [x] デフォルトコンテナイメージを `docker.io/zmkfirmware/zmk-build-arm:4.1` に更新

### テスト結果

| # | 検証項目 | キーボード | 結果 |
|---|----------|-----------|------|
| 1 | 単一ターゲットビルド | s3kb (s3kb_front) | ✅ 成功、モジュール検出動作 |
| 2 | 複数ターゲットバッチビルド | s3kb (front + back) | ✅ 1コンテナで2ターゲット、約68秒 |
| 3 | pristine フラグ | s3kb | ✅ `-p` フラグ正常動作 |
| 4 | 出力ファイル生成 | s3kb | ✅ .uf2 ファイル生成確認 |

### パフォーマンス比較

| 構成 | act (2/15) | Docker バッチ (2/16) | 改善 |
|------|------------|---------------------|------|
| s3kb (2ターゲット) | ~73秒 (2コンテナ) | ~68秒 (1コンテナ) | -5秒 (-7%) |
| 理論値 fish (5ターゲット) | ~2分30秒 (5コンテナ) | ~2分10秒 (1コンテナ) | -20秒 (-13%) |

**注**: west build 自体の時間は同じ。改善はコンテナ起動オーバーヘッドの削減による。

## Verification

### 動作確認コマンド

```bash
# 1. 初回ビルド（ワークスペース初期化）
./build.sh --init keyboards/zmk-config-s3kb/build.yaml

# 2. pristine リビルド
./build.sh keyboards/zmk-config-s3kb/build.yaml -p

# 3. 複数ターゲットのバッチビルド
./build.sh keyboards/zmk-config-fish/build.yaml -p

# 4. ターゲットフィルタリング
./build.sh keyboards/zmk-config-fish/build.yaml -t fish_left_central

# 5. モジュール検出テスト
mkdir -p zmk_modules/test-module/zephyr
echo "name: test-module" > zmk_modules/test-module/zephyr/module.yml
./build.sh keyboards/zmk-config-s3kb/build.yaml -t s3kb_front 2>&1 | grep "local module"

# 6. インタラクティブモード
./build.sh

# 7. リプレイ
./rebuild.sh
```

### 期待される出力

```
[21:41:23] detecting modules...
[21:41:23]   keyboard config module: zmk-config-s3kb
[21:41:23] executing batched build (2 target(s)) in container...
=== Building s3kb_front ===
...
=== Building s3kb_back ===
...
[21:43:28] done
```

## References

- [ADR: ビルドシステムを Docker 直接管理から act ベースに移行する](20260215-adr-build-system-docker-to-act-migration.md) - 本 ADR により Superseded
- [Design: ZMK モジュール統合の二重メカニズム](20260215-design-zmk-module-integration-dual-mechanism.md) - モジュール検出ロジックの詳細
- [Design: ZMK コードベースの取得・配置フロー](20260207-design-zmk-codebase-acquisition-flow.md)
- [Docker CLI Reference](https://docs.docker.com/engine/reference/commandline/cli/)
