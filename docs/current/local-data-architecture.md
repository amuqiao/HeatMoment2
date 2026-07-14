# 本地数据架构导览

本文面向后续开发者，说明 HeatMoment 当前本地数据闭环的核心边界。它只记录已经落地的 current 事实；未来 iCloud 同步和完整后台 GC 仍以 [`../plans/implementation-plan.md`](../plans/implementation-plan.md) 为准。

## 整体模型

HeatMoment 当前是单机优先的本地资料库应用。生产读写权威只有一套：

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
| 完整备份包 | 用户手动导出/导入 `.heatmomentbackup`，用于迁移或重装后整库恢复 | 导出只读；导入确认后 stage pending restore，冷启动替换本机库 | 不直接参与 |
| 本机安全点 | 系统自动维护最近 3 个 SQLite snapshot，供内部安全点和导入前 restore-safety 使用 | 创建 catalog/pin；恢复时替换本机库 | 不直接参与 |
| Markdown/PDF 导出 | 生成用户可读文件，不可导回恢复 | 否 | 不参与 |
| Asset reachability | 审计和受保护 cleanup 地基 | 维护操作可 finalize record / 清 orphan blob | 不表达同步 |
| iCloud 状态 | 当前只展示能力、网络和最近本地写入推导 | 否 | 尚未真实同步 |

## 代码分层

### Canonical Core

`Sources/HeatMoment/Persistence/Canonical/` 是本地资料库核心：

- `CanonicalStore.swift`：SQLite schema migration 和 GRDB read/write 入口。
- `CanonicalRecords.swift`：canonical value records，包括 lifecycle、mutation、asset pin、recovery point 和 library metadata。
- `CanonicalLibraryRuntime.swift`：生产和测试 runtime 装配。
- `CanonicalLibraryRepository.swift`：Moment/Tag 的主要读写事务边界。
- `CanonicalLibraryRepositorySupport.swift`：repository 支撑类型。
- `FileAssetStore.swift`：content-addressed 原图文件存储。

### Recovery Points

恢复点是本机安全网，不是用户可携带的外部备份包；设置页主备份模型是完整备份包。

- `CanonicalRecoveryPointStore.swift`：recovery point catalog、retention、asset manifest 和 recoveryPoint pin 写入。
- `CanonicalRecoveryPointSnapshotService.swift`：创建、校验、retention、目录清理的应用服务入口；内部 helper 保持文件内私有，避免绕过 `operationGate`。
- `CanonicalRecoveryCoordinator.swift`：设置页和写入触发器使用的恢复点应用服务边界。
- `CanonicalRestoreExecutor.swift`：stage、arm、boot replace、rollback 的执行器。
- `CanonicalRestoreTypes.swift`：boot restore、pending restore 和错误合同。
- `CanonicalBootRestoreGate.swift`：App 打开 runtime 前消费 armed pending restore。
- `CanonicalMigrationSafetyGate.swift`：破坏性迁移或切换前的安全点闸门。

### Backup Package

完整备份包是用户可见、可携带、可恢复的数据包。

- `BackupPackageTypes.swift`：`BackupPackageServicing`、manifest、payload、临时导出、导出完成、预览和导入准备类型。
- `BackupPackageArchive.swift`：自定义单文件容器，包含 magic、manifest length、manifest 和按 manifest 顺序写入的 payload；读取时校验相对路径、字节数、SHA-256 和尾部数据。
- `CanonicalBackupPackageService.swift`：完整备份包应用服务；导出准备时用 GRDB online backup 创建 SQLite snapshot，校验并复制 content-addressed 原图 blob，写入临时 `.heatmomentbackup`，系统分享/保存 completed 后才记录上次导出，并将分享源包标记为短期保留；导入时复制外部文件到 staging，校验 manifest / SQLite catalog / payload hash，取消确认或下次进入/导入前清理未确认 staging，确认后把资产写入当前 `FileAssetStore` 并复用 pending restore 冷启动替换链路。
- `BackupRestoreView.swift`：设置页“备份/还原”详情页，通过操作选择在导出备份和导入还原之间切换，并用单个主按钮执行当前操作；导入文件校验通过后直接弹出确认 sheet，展示最小预览和替换提示，不在页面主体展示内部恢复点或准备态。

当前完整备份包不压缩、不做增量、不替换或删除用户已有外部备份，也不记录用户最终保存路径；App 只记录上次系统分享/保存完成交接的导出时间。导出取消、分享中断或 App 被杀后重新进入页面，不会记录上次导出，并会清理遗留的未完成准备态临时包；导入不会把上次导出改成导入时间或备份包创建时间。已完成分享的源包用 marker 短期保留，超过保留窗口后再清理，避免系统 Files / iCloud Drive 保存收尾期间源文件已消失。

### Markdown/PDF Export

Markdown/PDF 导出是只读文件生成，不是备份恢复入口。

- `ExportTypes.swift`：`ExportRequest`、`ExportScope`、`ExportSnapshot`、`ExportShareTransaction` 和错误类型。
- `CanonicalExportSnapshotStore.swift`：从 canonical repository 读取导出快照。
- `ExportService.swift`：导出编排，负责 snapshot -> renderer -> writer -> share transaction，并在事务完成后清理临时副本。
- `ExportFileWriter.swift`：临时导出目录、Markdown/PDF 文件写入和失败清理。
- `MarkdownExportRenderer.swift`：Markdown 文本和相对附件路径渲染。
- `PDFExportRenderer.swift`：PDF 分页和图片嵌入。
- `ExportView.swift` / `ExportViewActions.swift` / `ExportViewState.swift` / `ExportStatusSections.swift`：设置页导出 UI、分享事务状态、系统分享承载和失败展示。

## 写入与恢复原则

普通写入成功后，`LocalLibraryMutationService` 会通知 `CanonicalLibraryService` 刷新 UI，并触发稳定变更恢复点。高风险操作前会同步创建 mutation safety 恢复点；创建失败则中止后续操作，不静默继续。

内部安全点恢复和完整备份包导入都复用同一条两段式 pending restore 链路：

```text
validate selected recovery point / validated backup package
  -> stage selected snapshot / imported snapshot
  -> create restore-safety recovery point
  -> update pending context
  -> arm pending restore
  -> next cold launch replaces local store before runtime opens
```

这样做的目的是让“准备恢复”和“真正替换 SQLite payload”分离。替换发生在 runtime 打开前；如果 rollback critical failure，启动会中止而不是继续使用不确定状态。完整备份包导入会在 arm 前把包内资产 blob 写入当前 `FileAssetStore` 并用 restore staging pin 保护，避免恢复后数据库引用缺失照片。

## Markdown/PDF 导出原则

Markdown/PDF 导出使用同一份 `ExportRequest` 和 `ExportSnapshot` 支撑两种格式。日期范围按整日边界查询；空范围失败，不生成空文档；照片开关关闭时不会读取或写出图片。

导出文件写在系统临时目录，进入导出页和每次新导出都会清理旧的 `HeatMoment-*` 包。导出失败会清理本次半成品包；导出成功后生成 `ExportShareTransaction` 并立即打开系统分享，分享完成或取消后结束事务并清理本次临时副本；系统分享返回错误时保留本次事务并允许重试分享；如果 App 在分享中或清理前被杀死，下次进入导出页会清理遗留临时副本。Markdown/PDF 导出不写 canonical store、不创建恢复点、不触发 iCloud 状态，也不能导回恢复。

## 验证入口

本地数据闭环的核心定向验证包括：

```bash
./scripts/test.sh --only HeatMomentTests/CanonicalRecoveryPointSnapshotServiceTests \
  --only HeatMomentTests/CanonicalRestoreExecutorTests \
  --only HeatMomentTests/BackupPackageServiceTests \
  --only HeatMomentTests/MarkdownExportServiceTests \
  --only HeatMomentTests/PDFExportServiceTests
```

阶段收口或共享基础设施变动后，再根据风险补跑 `./scripts/lint.sh`、`./scripts/test.sh --unit` 或 `./scripts/verify.sh`。
