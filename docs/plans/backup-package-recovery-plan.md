# 完整备份包与恢复重构关闭记录

本文保留 2026-07-13 完整备份包与恢复重构的关闭证据。已落地事实和能力边界维护在 [`../current/`](../current/README.md)，不在计划层重复维护第二套真相。

## Closed Scope

- 设置页“备份与恢复”已改为用户可见的 `.heatmomentbackup` 完整备份包入口。
- 原 Markdown/PDF 导出已在设置页命名为“阅读副本导出”，文案明确不能导回恢复。
- 本机 recovery point 已重定位为内部安全点：用于稳定变更、高风险写入、迁移和完整备份导入前 restore-safety，不再作为主备份模型展示给用户。
- 完整备份包导出每次生成新的完整包，不做增量，不替换或删除用户外部旧备份，不记录用户最终保存路径。
- 完整备份包导入先复制到 staging，校验 magic、manifest、payload 相对路径、byte count、SHA-256、尾部数据、SQLite catalog 和 asset manifest；用户确认后才创建恢复前安全点、stage pending restore、arm 下次冷启动替换。
- 恢复执行复用 canonical pending restore / cold boot gate，设置页不直接替换 SQLite。
- `.heatmomentbackup` UTI 和 `.heatmomentbackup` 扩展名已在 XcodeGen 生成的 app Info.plist 中注册。

## Current Sources

- as-built 总览：[`../current/README.md`](../current/README.md)
- 本地数据架构：[`../current/local-data-architecture.md`](../current/local-data-architecture.md)
- 实现真相：[`../current/implementation-truth.md`](../current/implementation-truth.md)
- 测试架构：[`../current/testing-architecture.md`](../current/testing-architecture.md)

## Verification Evidence

```bash
./scripts/gen.sh
./scripts/test.sh --only HeatMomentTests/BackupPackageServiceTests
./scripts/test.sh --only HeatMomentUITests/BackupRestoreUITests
```

结果：通过。`BackupPackageServiceTests` 覆盖完整包导出/预览、尾部篡改拒绝、payload hash 篡改拒绝与 staging 清理、跨 runtime 导入 staging、restore-safety、pending restore arm、保留策略失败后的 armed restore 结果、冷启动整库替换和照片恢复。`BackupRestoreUITests` 覆盖设置页完整备份包入口、旧恢复点 UI 不再展示、导出完整备份包和系统分享入口。

## Follow-Up

- iCloud 导入后的远端收敛、sync epoch/checkpoint 作废策略仍属于 [`implementation-plan.md`](implementation-plan.md) 的 iCloud follow-up。
- 完整后台 asset GC 调度、跨启动 export/import staging 对账和更完整的 pin 生命周期清理由 [`implementation-plan.md`](implementation-plan.md) 的 Asset GC Hardening 继续跟进。
- 当前外部备份包容器是未压缩单文件格式；如未来要改为压缩 archive，需要新增格式版本、迁移读取策略和相同级别的 hash/byte count/路径穿越测试。
