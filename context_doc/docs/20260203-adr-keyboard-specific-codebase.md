# ADR-001: キーボード毎に独立したコードベースを使用

## Status

Accepted

## Context

ZMKファームウェアのビルド環境において、複数のカスタムキーボード（fish, d3kb, d3kb2, s3kb, taiyaki）をサポートする必要がある。各キーボードは異なる機能要件を持ち、それぞれ異なるZMKモジュール（マウスジェスチャー、スクロールスナップ、PMW3610センサードライバーなど）に依存している。

これらの依存関係は各キーボードの`config/west.yml`マニフェストで定義され、`west update`によってフェッチされる。依存モジュールが異なるため、単一の共有コードベースでは依存関係の競合が発生する可能性がある。

## Decision

各キーボード設定をgitサブモジュールとして分離し、それぞれ独自の`zmk_work/`ディレクトリにZMKコードベースを持つ構造を採用する。

構造:
```
keyboards/
├── zmk-config-fish/
│   ├── config/west.yml      # fish固有の依存関係
│   └── zmk_work/zmk/        # fish用のZMKコードベース
├── zmk-config-d3kb/
│   ├── config/west.yml      # d3kb固有の依存関係
│   └── zmk_work/zmk/        # d3kb用のZMKコードベース
...
```

## Consequences

### Positive

- 各キーボードが独自のwest.ymlマニフェストで依存関係を完全に制御できる
- キーボード間の依存関係の競合が発生しない
- 各キーボードを独立してビルド・更新できる
- unified-zmk-config-templateとの互換性を維持し、GitHub Actionsでのビルドも可能

### Negative

- ディスク使用量が増加する（ZMKソースが各キーボードで複製される）
- 初回の`--init`に時間がかかる（各キーボードでwest updateが必要）

### Risks

- ZMKの更新タイミングがキーボード間で異なる可能性がある
  - 緩和策: 必要に応じて全キーボードに対して`--update`を実行

## Alternatives Considered

### Alternative 1: 共有ZMKコードベース

- **Pros**: ディスク容量の節約、一括更新が可能
- **Cons**: west.ymlマニフェストの競合、モジュールバージョンの統一が必要
- **Why rejected**: キーボード毎に異なるモジュール依存関係を持つため、実現不可能

### Alternative 2: モノレポ構造でwest.ymlを統合

- **Pros**: 単一のwest updateで全依存関係をフェッチ
- **Cons**: unified-zmk-config-templateとの互換性喪失、GitHub Actions CI/CDが使用不可
- **Why rejected**: 既存のZMKエコシステムとの互換性を維持する必要がある

## References

- [unified-zmk-config-template](https://github.com/zmkfirmware/unified-zmk-config-template)
- [West Manifest Documentation](https://docs.zephyrproject.org/latest/develop/west/manifest.html)
