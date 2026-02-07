# ~~Runbook: ZMK ファームウェアのビルド方法~~

> **⚠️ DEPRECATED (2026-02-07)**: このドキュメントは廃止されました。ビルドスクリプトは Python (`build.py`) から zsh (`build.sh`) に移行済みです。
>
> 最新の手順は [ビルドスクリプトの使い方 (build.sh)](20260207-howto-how-to-use-build-script.md) を参照してください。
>
> 移行の経緯は [ADR: ビルドスクリプトを Python から zsh に移行する](20260207-adr-build-script-python-to-zsh-migration.md) を参照してください。

---

<details>
<summary>旧手順（参考用）</summary>

## Overview

ZMK キーボードファームウェアをローカル環境でビルドする手順。

## When to Use

- キーマップや設定を変更した後にファームウェアをビルドしたいとき

## Prerequisites

- [ ] Docker が起動していること
- [ ] Python 仮想環境 `.venv/` が作成済みであること

## Procedure

### Step 1: 仮想環境の有効化

```bash
source .venv/bin/activate
```

---

### Step 2: ファームウェアのビルド

```bash
python3 build.py keyboards/<keyboard-name>/build.yaml -p
```

**yaml のパスは適宜変更する**

例:
```bash
python3 build.py keyboards/zmk-config-fish/build.yaml -p
```

**Expected Result**: `keyboards/<keyboard-name>/zmk_work/` に `.uf2` ファイルが生成される

</details>

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2026-02-03 | Claude | Initial version |
| 2026-02-07 | Claude | Deprecated — build.sh に移行済み |
