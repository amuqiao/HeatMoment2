# HeatMoment 数据生命周期实现计划

本文是数据生命周期专项 follow-up 计划，只记录本地数据闭环之后仍未完成的数据目标、实施顺序和验收条件。它不是全项目总计划；SwiftUI 应用骨架重构见 [`swiftui-foundation-refactor-plan.md`](swiftui-foundation-refactor-plan.md)。已落地事实进入 [`../current/`](../current/README.md)；产品语义以 [`../product-mental-model.md`](../product-mental-model.md) 为准。

## Planning Position

HeatMoment 是单机优先、小而美的个人日记 App。数据架构必须可靠、可恢复、可验证，但不能膨胀成账号系统、云备份平台或多人协同系统。

### 用户心智模型

```text
记录默认保存在本机
  -> App 自动保留最近 3 个本机恢复点
  -> 用户可从恢复点恢复，但不能删除恢复点
  -> 用户可导出 Markdown / PDF 阅读副本
  -> 后续可使用系统 iCloud 在自己的设备间同步
```

- App 使用无需登录，不引入 HeatMoment 账号。
- 本机保存是默认事实，不是用户要选择的模式。
- iCloud 同步依赖系统 Apple ID，只是后续跨设备收敛通道，不是 App 登录，也不叫云端备份。
- 自动恢复点是 App 内本机恢复点，最多保留 3 个，系统自动维护，用户只查看和恢复。
- Markdown / PDF 导出是只读副本，不用于恢复，不参与 iCloud 同步。

### 开发者心智模型

```text
SwiftUI / ViewModel
  -> CanonicalLibraryService / LocalLibraryMutationService
      -> CanonicalLibraryRepository
          -> GRDB + SQLite canonical store
          -> FileAssetStore
          -> CanonicalRecoveryCoordinator
          -> ExportService
          -> Optional Future iCloud Sync Service
```

- 本地权威固定为 `Canonical Repository + GRDB + SQLite + FileAssetStore`。
- projection 不做第二权威；首选同一 SQLite 库里的 derived tables/views 或可重建查询层。
- `mutation_log` 记录本地事实；后续 iCloud 的 `sync_outbox` 记录可重试同步意图；两者不能混用。
- iCloud 同步后置为独立计划，不能阻塞本地创建、编辑、删除、恢复、导出。

### 非目标

- 不做 App 账号、登录态、服务端用户模型或自建后端。
- 不做多人协作、实时协同编辑或共享资料库。
- v1 不做用户手动删除恢复点，也不做复杂 merge restore。
- v1 不把外部 `.heatmomentbackup` 文件作为主恢复模型；如需可分享备份文件，后续在自动恢复点稳定后单独设计。

## Current Baseline

- 本地读写权威、UI 主流程、恢复点、Markdown/PDF 导出和 UI 测试种子使用 canonical 架构，详见 [`../current/implementation-truth.md`](../current/implementation-truth.md)。
- 后续本地数据生命周期计划只基于 canonical store 演进。
- 设置页已经区分“备份与恢复”和“导出”；恢复点是系统自动维护的本机恢复点，导出是只读副本。
- 当前导出闭环支持全部或日期范围、Markdown/PDF、照片开关、失败重试和临时文件清理；它不写 canonical store、不创建恢复点、不参与 iCloud 同步，详见 [`../current/implementation-truth.md`](../current/implementation-truth.md)。
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

阶段内验证采用风险分层：实现小步优先运行相关单元测试、窄 UI 测试、`build`、`lint` 和 `diff-check`；阶段收口、跨 UI 主流程、发布前或修改共享基础设施时再跑全量 `verify.sh`。

| 范围 | 必测内容 |
| --- | --- |
| Canonical store | schema migration、启动 runtime、事务回滚、幂等写入、projection rebuild。 |
| 删除生命周期 | `active / softDeleted / purgePending / purged`、垃圾箱、彻底删除后不可被恢复路径复活。 |
| Asset pipeline | hash、引用、pin、GC、恢复点/导出/staging 期间不误删。 |
| 自动恢复点 | 最多 3 个、按时间淘汰、不可删除、列表可见、恢复预览、恢复失败不破坏现库。 |
| Restore | staging 校验、atomic replace、崩溃中断、`syncEpoch` 重建、旧 outbox/token 作废。 |
| Export | 全部/日期范围、照片开关、Markdown 相对链接、PDF 分页、图片嵌入、空范围失败、失败态、重试入口、临时文件清理、只读边界。 |
| Settings IA | 独立数据分组、iCloud/自动恢复点/导出详情页、面容解锁根页开关、无 App 登录入口。 |
| iCloud follow-up | 未登录、关闭 iCloud、单设备、两设备、Apple ID 变化、离线后恢复、图片同步、删除传播、冲突记录。 |

## Final Plan Acceptance

本地数据闭环已经进入 current。整份数据生命周期计划最终关闭还需要：

- iCloud 独立计划落地并通过真机矩阵验收。
- 完整 asset GC 执行入口落地，并证明不会误删 recovery/export/sync 仍需保护的 blob。
- current 文档持续保持 as-built 真相，不把已关闭阶段重新写成主动计划。
