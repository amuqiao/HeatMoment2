# 本地数据架构导览

本文面向后续开发者，说明 Moodments 当前本地数据闭环的核心边界。它只记录已经落地的 current 事实；未来 iCloud 同步和完整后台 GC 仍以 [`../plans/implementation-plan.md`](../plans/implementation-plan.md) 为准。

## 整体模型

Moodments 当前是单机优先的本地资料库应用。生产读写权威只有一套：

```text
SwiftUI / ViewModel
  -> CanonicalLibraryService / LocalLibraryMutationService
      -> CanonicalLibraryRepository
          -> CanonicalStore (GRDB + SQLite)
          -> FileAssetStore (content-addressed original assets)
```

`CanonicalStore` 保存 Moment、Tag、link、lifecycle、mutation log、恢复点 catalog 和 asset pin metadata。`FileAssetStore` 保存原图 bytes，SQLite 只保存 asset metadata、content hash 和关系顺序。

这套结构的关键约束是：**业务写入必须进入 canonical repository 或 canonical recovery 边界，导出只读，未来 iCloud 只能作为同步层接入，不应成为第二个本地权威。**

## 能力边界

| 能力 | 当前职责 | 是否写 canonical store | 是否参与 iCloud |
| --- | --- | ---: | ---: |
| 普通写入 | 创建、编辑、删除、恢复、标签变更 | 是 | 当前只更新启发式同步状态 |
| 本机恢复点 | 系统自动维护最近 3 个 SQLite snapshot，供用户恢复 | 创建 catalog/pin；恢复时替换本机库 | 不直接参与 |
| 导出 Markdown/PDF | 生成用户可读副本 | 否 | 不参与 |
| Asset reachability | 审计和受保护 cleanup 地基 | 维护操作可 finalize record / 清 orphan blob | 不表达同步 |
| iCloud 状态 | 当前只展示能力、网络和最近本地写入推导 | 否 | 尚未真实同步 |

## 代码分层

### Canonical Core

`Sources/Moodments/Persistence/Canonical/` 是本地资料库核心：

- `CanonicalStore.swift`：SQLite schema migration 和 GRDB read/write 入口。
- `CanonicalRecords.swift`：canonical value records，包括 lifecycle、mutation、asset pin、recovery point 和 library metadata。
- `CanonicalLibraryRuntime.swift`：生产和测试 runtime 装配。
- `CanonicalLibraryRepository.swift`：Moment/Tag 的主要读写事务边界。
- `CanonicalLibraryRepositorySupport.swift`：repository 支撑类型。
- `FileAssetStore.swift`：content-addressed 原图文件存储。

### Recovery Points

恢复点是本机安全网，不是外部备份包。

- `CanonicalRecoveryPointStore.swift`：recovery point catalog、retention、asset manifest 和 recoveryPoint pin 写入。
- `CanonicalRecoveryPointSnapshotService.swift`：创建、校验、retention、目录清理的应用服务入口；内部 helper 保持文件内私有，避免绕过 `operationGate`。
- `CanonicalRecoveryCoordinator.swift`：设置页和写入触发器使用的恢复点应用服务边界。
- `CanonicalRestoreExecutor.swift`：stage、arm、boot replace、rollback 的执行器。
- `CanonicalRestoreTypes.swift`：boot restore、pending restore 和错误合同。
- `CanonicalBootRestoreGate.swift`：App 打开 runtime 前消费 armed pending restore。
- `CanonicalMigrationSafetyGate.swift`：破坏性迁移或切换前的安全点闸门。

### Export

导出是只读副本生成，不是备份恢复入口。

- `ExportTypes.swift`：`ExportRequest`、`ExportScope`、`ExportSnapshot` 和结果/错误类型。
- `CanonicalExportSnapshotStore.swift`：从 canonical repository 读取导出快照。
- `ExportService.swift`：导出编排，负责 snapshot -> renderer -> writer。
- `ExportFileWriter.swift`：临时导出目录、Markdown/PDF 文件写入和失败清理。
- `MarkdownExportRenderer.swift`：Markdown 文本和相对附件路径渲染。
- `PDFExportRenderer.swift`：PDF 分页和图片嵌入。
- `ExportView.swift` / `ExportViewState.swift` / `ExportStatusSections.swift`：设置页导出 UI、`ExportView` 内部轻量状态和结果/失败展示。

## 写入与恢复原则

普通写入成功后，`LocalLibraryMutationService` 会通知 `CanonicalLibraryService` 刷新 UI，并触发稳定变更恢复点。高风险操作前会同步创建 mutation safety 恢复点；创建失败则中止后续操作，不静默继续。

用户恢复走两段式：

```text
validate selected recovery point
  -> stage selected snapshot
  -> create restore-safety recovery point
  -> update pending context
  -> arm pending restore
  -> next cold launch replaces local store before runtime opens
```

这样做的目的是让“准备恢复”和“真正替换 SQLite payload”分离。替换发生在 runtime 打开前；如果 rollback critical failure，启动会中止而不是继续使用不确定状态。

## 导出原则

导出使用同一份 `ExportRequest` 和 `ExportSnapshot` 支撑 Markdown/PDF 两种格式。日期范围按整日边界查询；空范围失败，不生成空文档；照片开关关闭时不会读取或写出图片。

导出文件写在系统临时目录，进入导出页和每次新导出都会清理旧的 `Moodments-*` 包。导出失败会清理本次半成品包；取消导出不会留下可见 package。导出不写 canonical store、不创建恢复点、不触发 iCloud 状态。

## 验证入口

本地数据闭环的核心定向验证包括：

```bash
./scripts/test.sh --only MoodmentsTests/CanonicalRecoveryPointSnapshotServiceTests \
  --only MoodmentsTests/CanonicalRestoreExecutorTests \
  --only MoodmentsTests/MarkdownExportServiceTests \
  --only MoodmentsTests/PDFExportServiceTests
```

阶段收口或共享基础设施变动后，再根据风险补跑 `./scripts/lint.sh`、`./scripts/test.sh --unit` 或 `./scripts/verify.sh`。
