# Design Document: ZMK コードベースの取得・配置フロー

## Overview

ZMK キーボードファームウェアのビルドフローにおいて、ZMK のソースコード及びその依存関係（Zephyr RTOS、HAL モジュール等）がどのように取得され、ファイルシステム上に配置されるかを記述する。

## Goals

- ZMK コードベースの取得メカニズムを明確にする
- `zmk_work/` ディレクトリ構造とその役割を文書化する
- West マニフェストによる依存解決の連鎖を説明する

## Non-Goals

- ビルドコマンド（`west build`）の詳細な引数やオプションの説明
- Docker コンテナのライフサイクル管理の詳細
- キーボード固有の設定（keymap、overlay）の説明

## Background

本リポジトリでは `build.py` がビルドオーケストレーターとして機能し、Docker コンテナ内で Zephyr の West ツールを使って ZMK コードベースを取得・管理する。各キーボード設定は git submodule として管理され、それぞれが独自の `west.yml` マニフェストを持つ。

## Design

### Architecture

```
リポジトリルート/
├── build.py                          # ビルドオーケストレーター
├── keyboards/
│   └── zmk-config-<name>/           # git submodule
│       ├── build.yaml               # ビルドターゲット定義
│       └── config/
│           └── west.yml             # West マニフェスト（ZMK取得元を定義）
└── zmk_work/
    └── zmk-config-<name>/           # workdir_top: キーボード毎のワークスペース
        ├── <shield>.uf2             # ビルド成果物
        └── zmk/                     # workdir: West ワークスペースルート
            ├── .west/config         # West 設定（manifest path = config）
            ├── config/              # keyboards/ から copytree されたマニフェスト
            │   └── west.yml
            ├── zmk/                 # ZMK 本体ソースコード (GitHub clone)
            │   └── app/             # ビルド対象アプリケーション
            │       └── west.yml     # ZMK の依存マニフェスト（連鎖 import）
            ├── zephyr/              # Zephyr RTOS (ZMK の west.yml 経由で取得)
            ├── modules/             # Zephyr 依存モジュール群
            ├── optional/            # オプショナル依存
            └── build/               # ビルド出力ディレクトリ
                └── <shield>/
                    └── zephyr/zmk.uf2
```

### Components

#### Component 1: build.py — zmkBuilder クラス

- **Purpose**: キーボード毎のビルドワークスペースのパス計算と初期化
- **Responsibilities**:
  - `workdir_top` の算出: `repo_root / "zmk_work" / container_name` (L110)
  - `workdir` の算出: `workdir_top / "zmk"` (L111)
  - `keyboards/<name>/config/` → `zmk_work/<name>/zmk/config/` へのコピー (L129, L134)
- **Key paths**:
  - `self.workdir_top` = `zmk_work/zmk-config-<name>/`
  - `self.workdir` = `zmk_work/zmk-config-<name>/zmk/`
  - `self.wconfdir` = `zmk_work/zmk-config-<name>/zmk/config/`

#### Component 2: West マニフェスト (west.yml)

- **Purpose**: ZMK とその依存関係の取得元・バージョンを宣言的に定義
- **構造**:
  ```yaml
  manifest:
    remotes:
      - name: zmkfirmware
        url-base: https://github.com/zmkfirmware
    projects:
      - name: zmk
        remote: zmkfirmware
        revision: main
        import: app/west.yml    # ← 二段階マニフェスト: ZMK の依存も連鎖取得
    self:
      path: config
  ```
- **連鎖インポート**: `import: app/west.yml` により、ZMK リポジトリ内の `app/west.yml` が自動読み込みされ、Zephyr RTOS・HAL・モジュール群が追加で定義・取得される
- **キーボード固有の追加モジュール**: fish キーボードのように `zmk-pmw3610-driver` 等を `projects` に追加可能

#### Component 3: Docker コンテナ (zmkContainer)

- **Purpose**: West コマンドの実行環境を提供
- **動作**: `zmk_work/<name>/` がコンテナにマウントされ、`west init` / `west update` / `west build` はすべてコンテナ内で実行される
- **副作用**: コンテナ内は root で動作するため、取得されたソースコード（`zmk/`, `zephyr/`, `modules/`）の所有者は root になる

### データフロー: 初期化時 (`--init`)

```
1. zmkBuilder.__init__()
   └── workdir_top.mkdir()              # zmk_work/<name>/ を作成

2. zmkBuilder.init()
   ├── zmkContainer(force_new=True)     # Docker コンテナを新規作成
   ├── shutil.rmtree(workdir)           # 既存の zmk/ を削除
   ├── workdir.mkdir()                  # zmk_work/<name>/zmk/ を作成
   ├── shutil.copytree(confdir, wconfdir)  # config/ を zmk/config/ にコピー
   └── container.exec("west init -l config/")  # West ワークスペースを初期化
       └── .west/config が生成される

3. zmkBuilder.update()
   ├── shutil.copytree(confdir, wconfdir)  # config/ を再コピー（最新化）
   └── container.exec("west update")       # マニフェストに基づき全依存を git clone
       ├── zmk/         ← github.com/zmkfirmware/zmk (main)
       ├── zephyr/      ← zmk/app/west.yml 経由
       ├── modules/     ← zmk/app/west.yml 経由
       └── optional/    ← zmk/app/west.yml 経由
```

### データフロー: ビルド時

```
4. zmkBuilder.build()
   ├── container.exec("west zephyr-export")  # Zephyr CMake パッケージを登録
   ├── shutil.copytree(boardsdir, wboardsdir)  # boards/ を zmk/config/boards/ にコピー
   └── container.exec("west build -s zmk/app ...")  # ZMK アプリをビルド
       └── uf2 → zmk_work/<name>/zmk/build/<shield>/zephyr/zmk.uf2
           └── shutil.copy → zmk_work/<name>/<shield>.uf2  # 成果物を workdir_top に配置
```

## Dependencies

- **West (Zephyr Meta Tool)**: マニフェストベースの依存管理ツール。`west init` でワークスペースを初期化し、`west update` で全プロジェクトをクローン
- **Docker**: `zmkfirmware/zmk-dev-arm:4.1` イメージで West/CMake/Ninja 等のビルドツールチェーンを提供
- **Git**: West が内部的に `git clone` を使用してZMK・Zephyr等を取得

## References

- [キーボード毎に独立したコードベースを使用 (ADR)](../adr/20260203-0000-keyboard-specific-codebase.md)
- [ZMK ファームウェアのビルド方法 (Runbook)](../runbook/20260203-0000-zmk-firmware-build.md)
- [Zephyr West Manifest Documentation](https://docs.zephyrproject.org/latest/develop/west/manifest.html)
