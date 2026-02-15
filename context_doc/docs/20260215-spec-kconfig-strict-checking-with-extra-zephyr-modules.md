# 機能仕様: EXTRA_ZEPHYR_MODULES 使用時の Kconfig 厳格チェック

**⚠️ 更新 (2026-02-15)**: この仕様書の初期仮説は部分的に誤りであることが判明しました。詳細は「技術的訂正」セクションを参照してください。

## 概要

~~Zephyr ビルドシステムは、`EXTRA_ZEPHYR_MODULES` CMake 変数を通じてモジュールが追加された際、Kconfig の厳格な検証モードを自動的に有効化する。このモードでは、すべての Kconfig 警告がエラーとして扱われ、ビルドが中断される。この挙動は ZMK のカスタムドライバ開発において、上流 ZMK コードベースの既存の警告によってビルドが失敗するという問題を引き起こす。~~

**訂正後の理解**: Zephyr ビルドシステムの `kconfig.py` は、デフォルトでいかなる Kconfig 警告もエラーとして扱い、ビルドを中断する。`EXTRA_ZEPHYR_MODULES` の使用は厳格チェックを「発動」するのではなく、モジュールが正しく認識されない場合に undefined symbol 警告を引き起こし、その結果としてビルドが失敗する。環境変数 `KCONFIG_WARN_UNDEF=n` を設定することで警告を抑制可能。

## 動機

ZMK キーボードファームウェアの開発において、カスタムドライバやモジュールを統合する必要がある場合、開発者は `EXTRA_ZEPHYR_MODULES` を使用してモジュールをビルドシステムに注入する。しかし、モジュールの Kconfig が正しく読み込まれない場合、undefined symbol 警告が発生し、Zephyr の kconfig.py がビルドを中断する。

この仕様書は、初期の誤解と、コード調査によって明らかになった実際のメカニズムを文書化し、CI と等価なローカルビルド環境を構築するための知見を提供する。

## スコープ

- **対象範囲**:
  - `EXTRA_ZEPHYR_MODULES` 使用時の Kconfig 厳格チェックの発動条件
  - ビルド失敗の具体的なメカニズム
  - 試行された回避策とその結果
  - 現在の技術的制約

- **対象外**:
  - Zephyr のソースコード改変による根本的な解決策
  - ZMK 上流への警告修正パッチの提出
  - `EXTRA_ZEPHYR_MODULES` を使用しない代替アーキテクチャの詳細設計

## 動作

### 入力

以下のいずれかの条件で機能が発動する:

1. **モジュール注入**: CMake に `-DEXTRA_ZEPHYR_MODULES=/path/to/module` 引数を渡す
2. **モジュール自動検出**: ビルドワークフローが `zmk_modules/` ディレクトリ内のモジュールを検出し、自動的に `EXTRA_ZEPHYR_MODULES` に追加する
3. **キーボードコンフィグモジュール**: キーボードコンフィグリポジトリ自体が `zephyr/module.yml` を持ち、`cmake:` または `kconfig:` エントリが宣言されている場合

### 通常フロー

1. Zephyr ビルドシステムが `EXTRA_ZEPHYR_MODULES` 変数の存在を検出する
2. Kconfig の厳格検証モードが自動的に有効化される（`srctree` モジュールのみの場合でも適用）
3. すべての Kconfig ファイルが処理される（モジュール自身だけでなく、ZMK 上流のコードベース全体を含む）
4. 警告が検出された場合:
   - 通常モード: 警告として出力されるが、ビルドは続行される
   - 厳格モード: 警告がエラーに昇格され、以下のメッセージと共にビルドが中断される
     ```
     Aborting due to Kconfig warnings
     ```
5. モジュール自体に問題がなくても、ZMK 上流のコードベースに警告が存在する場合、ビルドは失敗する

### 出力 / 結果

#### 成功時（モジュールなし）

- Kconfig 警告は表示されるが、ビルドは続行される
- ファームウェアイメージ（`.uf2`）が正常に生成される

#### 失敗時（モジュールあり）

- 以下のようなエラーメッセージが表示される:
  ```
  warning: USB_DEVICE_PID (defined at drivers/usb/device/Kconfig:87) has non-default value 0x0.
  Should it only be set via Kconfig.defconfig files?

  Aborting due to Kconfig warnings
  CMake Error at zephyr/cmake/kconfig.cmake:358 (message):
    command failed with return code: 1
  ```
- ビルドは中断され、ファームウェアイメージは生成されない

### エラーケース

| 条件 | 動作 |
|------|------|
| モジュールが追加されているが、上流 ZMK に Kconfig 警告が存在する | ビルドがエラーで中断される（本仕様で説明する主要な問題） |
| `EXTRA_ZEPHYR_MODULES` が空文字列に設定されている | 厳格チェックは発動しない（空でない場合のみ発動） |
| モジュールに `module.yml` があるが `kconfig:` エントリがない | 厳格チェックは発動する（`kconfig:` の有無は無関係） |
| `KCONFIG_WARN_UNDEF=n` 環境変数を設定する | 効果なし（厳格モード設定が優先される） |
| `-DKCONFIG_WARN_UNDEF_ASSIGN=n` CMake 引数を渡す | 効果なし（Kconfig 処理前に評価される設定ではない） |
| `CONFIG_KCONFIG_WARN_AS_ERROR=n` をシールド設定に追加する | 効果なし（このシンボルは存在しない） |

### エッジケース

- **空のモジュール追加**: `EXTRA_ZEPHYR_MODULES=/path/to/empty/dir` でも厳格チェックは発動する（モジュールの内容は無関係）
- **srctree のみのモジュール**: Kconfig や CMake を宣言しないモジュールでも厳格チェックは発動する
- **複数モジュール**: モジュールが複数ある場合も、いずれか一つでも `EXTRA_ZEPHYR_MODULES` に含まれていれば厳格チェックが発動する
- **CI vs ローカル**: CI 環境（GitHub Actions の `build-user-config.yml`）では自動的にモジュールが注入されるため、警告がない上流 ZMK ブランチを使用する必要がある。ローカル環境では `zmk_modules/` を空にすることで回避可能

## 制約

- ~~**回避不可**: Zephyr ビルドシステムの仕様として、`EXTRA_ZEPHYR_MODULES` の使用と厳格チェックは不可分である~~ → **訂正**: `KCONFIG_WARN_UNDEF=n` で回避可能
- ~~**環境変数無効**: `KCONFIG_WARN_UNDEF=n` などの環境変数は厳格モード下では効果を持たない~~ → **訂正**: 環境変数は有効
- **モジュール認識必須**: カスタムドライバを統合する場合、Zephyr モジュール構造（`zephyr/module.yml` の適切な設定）が必須。設定が不完全だとドライバの Kconfig が読み込まれず、undefined symbol 警告が発生する
- **CI との差異**: CI（`build-user-config.yml`）はキーボード設定リポジトリ自体を `ZMK_EXTRA_MODULES` でモジュールとして注入するため、`module.yml` の `kconfig:` / `cmake:` 設定が自動的に認識される。ローカル環境では同様の注入を行わない限り、同じ挙動にならない

## 例

### 例1: モジュールなしのビルド（成功）

**入力**:
```bash
west build -s zmk/app -b xiao_ble -- \
  -DSHIELD=xiaord \
  -DZMK_CONFIG=/workspace/config \
  -DBOARD_ROOT=/workspace/config
```

**結果**:
```
warning: USB_DEVICE_PID (defined at drivers/usb/device/Kconfig:87) has non-default value 0x0.
warning: USB_DEVICE_MANUFACTURER (defined at drivers/usb/device/Kconfig:96) has non-default value "zmkfirmware".

[... ビルド続行 ...]

[100%] Built target zephyr
```

ファームウェアイメージ `zmk.uf2` が正常に生成される。警告は表示されるが、ビルドは成功する。

### 例2: カスタムドライバモジュール追加（失敗）

**入力**:
```bash
west build -s zmk/app -b xiao_ble -- \
  -DSHIELD=xiaord \
  -DZMK_CONFIG=/workspace/config \
  -DBOARD_ROOT=/workspace/config \
  -DEXTRA_ZEPHYR_MODULES=/workspace/zmk_modules/chsc6x-custom
```

**結果**:
```
warning: USB_DEVICE_PID (defined at drivers/usb/device/Kconfig:87) has non-default value 0x0.
Should it only be set via Kconfig.defconfig files?

warning: USB_DEVICE_MANUFACTURER (defined at drivers/usb/device/Kconfig:96) has non-default value "zmkfirmware".
Should it only be set via Kconfig.defconfig files?

Aborting due to Kconfig warnings

CMake Error at zephyr/cmake/kconfig.cmake:358 (message):
  command failed with return code: 1
```

ビルドは中断され、ファームウェアイメージは生成されない。カスタムドライバモジュール自体には問題がないにもかかわらず、上流 ZMK の既存の警告が原因でビルドが失敗する。

### 例3: 試行した回避策（すべて失敗）

#### 試行1: 環境変数で警告を無効化
```bash
export KCONFIG_WARN_UNDEF=n
west build ...
```
**結果**: 効果なし。厳格モードが優先される。

#### 試行2: CMake 引数で警告設定を上書き
```bash
west build ... -- -DKCONFIG_WARN_UNDEF_ASSIGN=n
```
**結果**: 効果なし。この設定は Kconfig 処理に影響しない。

#### 試行3: シールド設定でエラー無効化
```conf
# xiaord.conf
CONFIG_KCONFIG_WARN_AS_ERROR=n
```
**結果**: 効果なし。このシンボルは存在しない。

#### 試行4: モジュールから Kconfig を除外
```yaml
# zephyr/module.yml
build:
  cmake: .
  # kconfig: Kconfig  ← コメントアウト
```
**結果**: 効果なし。`EXTRA_ZEPHYR_MODULES` の存在のみで厳格チェックが発動する。

## 依存関係

この挙動は以下のシステムに依存する:

- **Zephyr ビルドシステム**: `cmake/kconfig.cmake` および `scripts/kconfig/` 内のスクリプト群
- **ZMK 上流コードベース**: `drivers/usb/device/Kconfig` などの Kconfig ファイルの警告状態
- **act ローカルビルド環境**: `build-local.yml` ワークフローと `build.sh` スクリプトの実装
- **Docker コンテナ**: `zmkfirmware/zmk-build-arm:stable` イメージに含まれる Zephyr/CMake バージョン

## 技術的訂正

コード調査（`kconfiglib.py`, `kconfig.py`, `zephyr_module.cmake`, ZMK `app/CMakeLists.txt`）の結果、以下が明らかになった:

### 誤解していた点

1. **`EXTRA_ZEPHYR_MODULES` が厳格チェックを発動する**: 誤り。`kconfig.py:122-127` は `EXTRA_ZEPHYR_MODULES` の有無に関わらず、ANY warning で `sys.exit()` を呼び出す。
2. **環境変数が無効**: 誤り。`kconfiglib.py` は `KCONFIG_WARN_UNDEF` 環境変数を正しく読み取り、`n` の場合は undefined symbol 警告を抑制する。
3. **`ZMK_EXTRA_MODULES` と `EXTRA_ZEPHYR_MODULES` が異なる**: 誤り。ZMK `app/CMakeLists.txt:6` で両者は `ZEPHYR_EXTRA_MODULES` に統合され、`zephyr_module.cmake:39` で同じ `--extra-modules` 引数となる。

### 実際のメカニズム

1. **モジュール検出**: `zephyr_module.py:575` は `extra_modules` パラメータの有無で `workspace_extra` フラグを設定するが、これは strict checking とは無関係。無効なモジュール（`module.yml` なし）が fatal error になるだけ。
2. **警告→エラー変換**: `kconfig.py:100` でシンボル評価を強制し、`kconfig.py:122` で `kconf.warnings` が空でない場合に abort。`error_out` パラメータがデフォルトで True であり、EXTRA_ZEPHYR_MODULES とは独立している。
3. **undefined symbol 警告の発生源**: モジュールの `kconfig:` エントリが `module.yml` に正しく設定されていないと、Kconfig ファイルが読み込まれず、そのモジュール固有のシンボルへの参照が undefined 扱いになる。

### 結論

当初観察されたビルド失敗は、「`EXTRA_ZEPHYR_MODULES` が厳格チェックを発動する」のではなく、「モジュールの Kconfig が読み込まれなかったために undefined symbol 警告が発生し、デフォルトで有効な警告→エラー変換によってビルドが中断された」ことが原因だった。CI では `ZMK_EXTRA_MODULES` でキーボード設定リポジトリ自体を注入するため、`module.yml` の設定が有効になり、Kconfig が正しく読み込まれる。ローカル環境でも同様の注入を行えば、CI と等価なビルドが可能になる。

## 参考資料

- [20260215-design-zmk-module-integration-dual-mechanism.md](./20260215-design-zmk-module-integration-dual-mechanism.md) - ZMK モジュール統合の二重メカニズム
- [20260215-handoff-chsc6x-custom-driver-integration-attempt.md](./20260215-handoff-chsc6x-custom-driver-integration-attempt.md) - カスタムドライバ統合試行の詳細記録
- Zephyr Documentation: [Kconfig - Tips and Best Practices](https://docs.zephyrproject.org/latest/build/kconfig/tips.html)
- ZMK Documentation: [New Keyboard Shield](https://zmk.dev/docs/development/new-shield)

### コード参照

- `zmk_work/*/zmk/zephyr/scripts/kconfig/kconfiglib.py` - `KCONFIG_WARN_UNDEF` 環境変数チェック
- `zmk_work/*/zmk/zephyr/scripts/kconfig/kconfig.py:122-127` - 警告からの abort ロジック
- `zmk_work/*/zmk/zmk/app/CMakeLists.txt:6` - `ZMK_EXTRA_MODULES` → `ZEPHYR_EXTRA_MODULES` 変換
- `zmk_work/*/zmk/zephyr/cmake/modules/zephyr_module.cmake:39` - `EXTRA_ZEPHYR_MODULES` → `--extra-modules` 変換
- `zmk_work/*/zmk/zephyr/scripts/zephyr_module.py:575` - `workspace_extra` フラグ設定（strict checking とは無関係）
