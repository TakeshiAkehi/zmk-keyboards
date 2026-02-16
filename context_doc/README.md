# Document Index

| Title | Path | Type | Keywords | Date |
|-------|------|------|----------|------|
| キーボード毎に独立したコードベースを使用 | [20260203-adr-keyboard-specific-codebase](docs/20260203-adr-keyboard-specific-codebase.md) | ADR | zmk, west-manifest, submodule, dependency-isolation | 2026-02-03 |
| ~~ZMK ファームウェアのビルド方法~~ (DEPRECATED) | [20260203-runbook-zmk-firmware-build](docs/20260203-runbook-zmk-firmware-build.md) | Runbook | zmk, docker, build, firmware, python | 2026-02-03 |
| Zephyr 3.5 → 4.1 マイグレーション | [20260205-handoff-zephyr-4-1-migration](docs/20260205-handoff-zephyr-4-1-migration.md) | Handoff | zephyr, migration, pmw3610, nfc, devicetree | 2026-02-05 |
| ZMK Zephyr 3.5 → 4.1 マイグレーション | [20260206-howto-zmk-zephyr-4-1-migration](docs/20260206-howto-zmk-zephyr-4-1-migration.md) | How-To | zmk, zephyr, migration, pmw3610, nfc-pins, kconfig | 2026-02-06 |
| ZMK Zephyr 4.1 マイグレーション作業状況 | [20260206-handoff-zephyr-4-1-migration-status](docs/20260206-handoff-zephyr-4-1-migration-status.md) | Handoff | zmk, zephyr, migration, blocker, build-status | 2026-02-06 |
| ZMK コードベースの取得・配置フロー | [20260207-design-zmk-codebase-acquisition-flow](docs/20260207-design-zmk-codebase-acquisition-flow.md) | Design | zmk, west, codebase-acquisition, zmk_work, dependency-resolution | 2026-02-07 |
| ビルドスクリプトを Python から zsh に移行する | [20260207-adr-build-script-python-to-zsh-migration](docs/20260207-adr-build-script-python-to-zsh-migration.md) | ADR | build-script, zsh, fzf, docker-cli, python-migration | 2026-02-07 |
| ビルドスクリプトの使い方 (build.sh) | [20260207-howto-how-to-use-build-script](docs/20260207-howto-how-to-use-build-script.md) | How-To | build-script, bash, zsh, docker, fzf, firmware | 2026-02-07 |
| ローカルモジュールオーバーライド機構 | [20260207-design-local-module-override](docs/20260207-design-local-module-override.md) | Design | zmk, zephyr-modules, EXTRA_ZEPHYR_MODULES, docker-mount, local-development | 2026-02-07 |
| ビルドシステムを Docker 直接管理から act ベースに移行する | [20260215-adr-build-system-docker-to-act-migration](docs/20260215-adr-build-system-docker-to-act-migration.md) | ADR | act, github-actions, docker, build-system, ci-local-parity | 2026-02-15 |
| ZMK モジュール統合の二重メカニズム | [20260215-design-zmk-module-integration-dual-mechanism](docs/20260215-design-zmk-module-integration-dual-mechanism.md) | Design | zmk-modules, local-development, ci-integration, EXTRA_ZEPHYR_MODULES, board-root | 2026-02-15 |
| カスタムCHSC6Xドライバ統合の試行と課題 | [20260215-handoff-chsc6x-custom-driver-integration-attempt](docs/20260215-handoff-chsc6x-custom-driver-integration-attempt.md) | Handoff | chsc6x, custom-driver, zephyr-module, kconfig, devicetree | 2026-02-15 |
| EXTRA_ZEPHYR_MODULES 使用時の Kconfig 厳格チェック | [20260215-spec-kconfig-strict-checking-with-extra-zephyr-modules](docs/20260215-spec-kconfig-strict-checking-with-extra-zephyr-modules.md) | Spec | zephyr, kconfig, EXTRA_ZEPHYR_MODULES, strict-checking, module-integration | 2026-02-15 |
| act ベースビルドシステムから Docker 直接管理に回帰する | [20260216-adr-act-to-docker-direct-migration](docs/20260216-adr-act-to-docker-direct-migration.md) | ADR | docker, build-system, performance, batch-execution, act-removal | 2026-02-16 |
