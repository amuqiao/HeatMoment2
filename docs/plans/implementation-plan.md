# HeatMoment 数据生命周期实现计划

本文是数据生命周期专项 follow-up 计划，只记录本地数据闭环之后仍未完成的数据目标、实施顺序和验收条件。它不是全项目总计划；SwiftUI 应用骨架重构见 [`swiftui-foundation-refactor-plan.md`](swiftui-foundation-refactor-plan.md)。已落地事实进入 [`../current/`](../current/README.md)；产品语义以 [`../product-mental-model.md`](../product-mental-model.md) 为准。

## Planning Position

HeatMoment 是单机优先、小而美的个人日记 App。数据架构必须可靠、可恢复、可验证，但不能膨胀成账号系统、云备份平台或多人协同系统。

### 用户心智模型

```text
记录默认保存在本机
  -> 用户可手动导出完整 `.heatmomentbackup` 备份包
  -> 用户可从完整备份包整库恢复
  -> App 内部自动保留本机安全点，供导入前、危险操作前和迁移前回滚
  -> 用户可导出 Markdown / PDF 阅读副本
  -> 后续可使用系统 iCloud 在自己的设备间同步
```

- App 使用无需登录，不引入 HeatMoment 账号。
- 本机保存是默认事实，不是用户要选择的模式。
- iCloud 同步依赖系统 Apple ID，只是后续跨设备收敛通道，不是 App 登录，也不叫云端备份。
- 完整备份包是用户可见的数据安全主模型；关闭证据见 [`backup-package-recovery-plan.md`](backup-package-recovery-plan.md)，as-built 真相见 [`../current/local-data-architecture.md`](../current/local-data-architecture.md)。
- 自动恢复点重定位为 App 内本机安全点，最多保留 3 个，系统自动维护，默认不作为主备份模型展示。
- Markdown / PDF 导出是只读副本，不用于恢复，不参与 iCloud 同步。

### 开发者心智模型

```text
SwiftUI / ViewModel
  -> CanonicalLibraryService / LocalLibraryMutationService
      -> CanonicalLibraryRepository
          -> GRDB + SQLite canonical store
          -> FileAssetStore
          -> CanonicalRecoveryCoordinator
          -> BackupPackage / DocumentExport services
          -> Optional Future iCloud Sync Service
```

- 本地权威固定为 `Canonical Repository + GRDB + SQLite + FileAssetStore`。
- projection 不做第二权威；首选同一 SQLite 库里的 derived tables/views 或可重建查询层。
- `mutation_log` 记录本地事实；后续 iCloud 的 `sync_outbox` 记录可重试同步意图；两者不能混用。
- iCloud 同步后置为独立计划，不能阻塞本地创建、编辑、删除、恢复、导出。

### 非目标

- 不做 App 账号、登录态、服务端用户模型或自建后端。
- 不做多人协作、实时协同编辑或共享资料库。
- v1 不做用户手动删除本机安全点，也不做复杂 merge restore。
- 完整 `.heatmomentbackup` 备份包、导入恢复和本机安全点重定位已关闭；本文不重复维护备份包格式合同。

## Current Baseline

- 本地读写权威、UI 主流程、完整备份包、本机安全点、Markdown/PDF 阅读副本导出和 UI 测试种子使用 canonical 架构，详见 [`../current/implementation-truth.md`](../current/implementation-truth.md)。
- 后续本地数据生命周期计划只基于 canonical store 演进。
- 设置页当前已区分“备份与恢复”和“阅读副本导出”；“备份与恢复”指完整 `.heatmomentbackup` 备份包，本机 recovery point 只作为内部安全点。
- 当前导出闭环支持日期范围、Markdown/PDF、照片开关、失败重试和临时文件清理；它不写 canonical store、不创建恢复点、不参与 iCloud 同步，详见 [`../current/implementation-truth.md`](../current/implementation-truth.md)。
- M-architecture-final 已把本地数据闭环的可复用心智模型整理到 [`../current/local-data-architecture.md`](../current/local-data-architecture.md)，并将导出、恢复点 snapshot 和 restore 类型合同按职责拆分为更小文件。
- 当前 iCloud 仍只有能力/网络/最近本地写入时间的启发式状态展示；尚未实现真实 CloudKit 同步状态机、多设备收敛、冲突记录或重试队列。
- 当前 asset reachability、pin-aware dry-run、DB orphan record finalizer 和 orphan blob cleanup 已有维护地基；完整后台 GC 调度、export/sync pin 生命周期尚未实现。

## Active Plan

### 1. iCloud Sync Follow-up Plan

目标：在不改变本地 canonical 权威、不引入 App 登录、不把 iCloud 表达成“云端备份”的前提下，实现系统 iCloud 私有库同步。

必须设计：

- CloudKit custom zone / record mapper / schema version。
- `sync_outbox`、checkpoint、重试、幂等写入和失败可见状态。
- Apple ID 不可用、iCloud 关闭、网络不可达、账号变化、配额/权限失败的用户可理解状态。
- Moment、Tag、asset metadata、tombstone、mutation 顺序和图片文件同步策略。
- 删除传播、恢复点与同步边界、冲突记录和最小冲突 UI。
- CloudKit import/export 不能绕过 canonical 事务边界；恢复完成后需要新的 sync epoch / checkpoint 规则处理远端收敛，不能把本机恢复点表达成云备份。
- asset pin 的 `sync` owner 只能由真实同步任务持有和释放。
- 单设备、两设备、离线后恢复、图片同步、删除传播、账号变化的真机矩阵。

验收：

- 本地创建/编辑/软删/恢复/彻底删除不依赖网络成功。
- 同一 Apple ID 下两台设备最终收敛，且不会把本机恢复点当作跨设备云备份。
- 弱网、重复同步、应用被杀、CloudKit 暂不可用时有确定行为，不静默丢数据。

### 2. Asset GC Hardening

目标：把当前 asset reachability / dry-run / cleanup 地基升级为可安全运行的完整维护流程。

必须设计：

- recovery point、restore staging、export job、sync job 的 content-hash pin 生命周期。
- 完整 GC 执行入口、节流和失败上报。
- 跨进程或后台任务场景下的持久 staging / pin 方案。
- 数据库 metadata 与文件系统 blob 的一致性审计和修复边界。

验收：

- 加图、删图、恢复、彻底删除、恢复点保留、导出和同步期间都不会误删资产。
- GC 执行前后有可审计计划和结果；blocking issue 不会被静默跳过。
- 清理流程不依赖内存态，不吞掉文件系统或数据库错误。

## Verification Matrix

阶段内验证采用风险分层：实现小步优先运行相关单元测试、窄 UI 测试、`build`、`lint` 和 `diff-check`；阶段收口、跨 UI 主流程、发布前或修改共享基础设施时再跑全量 `verify.sh`。完整备份包、阅读副本命名和本机安全点重定位已关闭；本文只保留 iCloud 与 asset GC 的数据生命周期 follow-up 验收。

| 范围 | 必测内容 |
| --- | --- |
| iCloud schema / outbox | CloudKit schema、`sync_outbox`、checkpoint、幂等 key、重试次数、终态失败记录和 migration 测试。 |
| iCloud availability | 未登录、关闭 iCloud、网络不可达、CloudKit 权限/配额失败、账号变化、前台 resume 补偿同步。 |
| iCloud convergence | 单设备、两设备、离线后恢复、图片同步、删除传播、冲突记录、重复同步不重复写入。 |
| Restore / sync boundary | 任意恢复完成后生成新 `syncEpoch`，旧 checkpoint/outbox/token 作废；远端收敛策略有确定测试。 |
| Asset pin lifecycle | recovery point、restore staging、backup package、export job、sync job 的 content-hash pin owner 创建、释放和失败清理。 |
| Asset GC execution | dry-run、blocking issue、finalize unlinked records、orphan blob cleanup、跨启动残留 staging 对账。 |
| Regression boundary | 已落地完整备份包导出/导入恢复和阅读副本路径不被 iCloud/GC follow-up 改坏。 |

阶段内最小验证由对应实现阶段细化；至少需要覆盖：

```bash
./scripts/test.sh --only HeatMomentTests/CanonicalAssetReachabilityServiceTests \
  --only HeatMomentTests/CanonicalAssetPinStoreTests \
  --only HeatMomentTests/CanonicalRestoreExecutorTests

./scripts/build.sh
```

iCloud 真机阶段必须补充 CloudKit 单设备/双设备矩阵；阶段收口运行：

```bash
./scripts/verify.sh
```

## Final Plan Acceptance

本地数据闭环已经进入 current。整份数据生命周期计划最终关闭还需要：

- iCloud 独立计划落地并通过真机矩阵验收。
- 已落地完整备份包、阅读副本和本机安全点的 as-built 真相持续保留在 current；本文不重新拥有该关闭计划。
- 完整 asset GC 执行入口落地，并证明不会误删 recovery/export/sync 仍需保护的 blob。
- current 文档持续保持 as-built 真相，不把已关闭阶段重新写成主动计划。
