# 完整备份包与恢复重构关闭记录

本文保留 2026-07-13 完整备份包与恢复重构的关闭证据。已落地事实和能力边界维护在 [`../current/`](../current/README.md)，不在计划层重复维护第二套真相。

## Closed Scope

- 完整备份包、导入还原、本机安全点重定位和 Markdown/PDF 导出命名的重构计划已关闭。
- 本文件不继续维护 as-built 命名、页面行为或格式合同；当前事实以 `docs/current/` 为准。
- 下方只保留关闭时的验证证据和未完成 follow-up 指向。

## Current Sources

- as-built 总览：[`../current/README.md`](../current/README.md)
- 本地数据架构：[`../current/local-data-architecture.md`](../current/local-data-architecture.md)
- 实现真相：[`../current/implementation-truth.md`](../current/implementation-truth.md)
- 测试架构：[`../current/testing-architecture.md`](../current/testing-architecture.md)

## Verification Evidence

```bash
./scripts/build.sh
./scripts/test.sh --only HeatMomentTests/BackupPackageServiceTests
./scripts/test.sh --only HeatMomentUITests/BackupRestoreUITests
```

结果：通过。`BackupPackageServiceTests` 覆盖临时完整包准备/预览、准备后不记录上次备份、完成提交后记录并清理、清理失败时仍保留已完成记录并返回 cleanup 状态、取消后不记录并清理、摘要读取不销毁 active 准备态、显式清理遗留准备态临时包、尾部篡改拒绝、payload hash 篡改拒绝与 staging 清理、跨 runtime 导入 staging、restore-safety、pending restore arm、保留策略失败后的 armed restore 结果、冷启动整库替换和照片恢复。`BackupRestoreUITests` 覆盖设置页极简完整备份入口、旧恢复点 UI 和旧二步导出结果区不再展示。

## Follow-Up

- iCloud 导入后的远端收敛、sync epoch/checkpoint 作废策略仍属于 [`implementation-plan.md`](implementation-plan.md) 的 iCloud follow-up。
- 完整后台 asset GC 调度、import staging 对账和更完整的 pin 生命周期清理由 [`implementation-plan.md`](implementation-plan.md) 的 Asset GC Hardening 继续跟进。
- 当前外部备份包容器是未压缩单文件格式；如未来要改为压缩 archive，需要新增格式版本、迁移读取策略和相同级别的 hash/byte count/路径穿越测试。
