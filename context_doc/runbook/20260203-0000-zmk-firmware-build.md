# Runbook: ZMK ファームウェアのビルド方法

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

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2026-02-03 | Claude | Initial version |
