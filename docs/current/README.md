# 当前实现真相

本文是 SwiftUI 版 Moodments 的 current 入口，只记录当前代码已经落地的事实、已知偏离和验证基线。产品公理以 [`../product-mental-model.md`](../product-mental-model.md) 为准；未来计划进入 [`../plans/implementation-plan.md`](../plans/implementation-plan.md)。

## 文档边界

`current` 回答“现在实际怎么实现”。它不承诺未来优化，不替代计划层，也不把 Flutter 版实现细节当作 SwiftUI 事实。当前数据权威是 `Canonical Repository + GRDB + SQLite + FileAssetStore`，旧本地存储实现已经从生产源码和旧架构测试中清理。

| 文件 | 职责 |
| --- | --- |
| [`implementation-truth.md`](implementation-truth.md) | SwiftUI 版当前 as-built 架构、界面流、主题/时间轴/设置等落地事实与偏离 |
| [`local-data-architecture.md`](local-data-architecture.md) | 本地 canonical store、恢复点、导出和未来 iCloud 接入边界的开发者导览 |
| [`testing-architecture.md`](testing-architecture.md) | 当前 XCTest/XCUITest 入口、数据隔离、UI 测试 launch arguments 与维护边界 |
| 本文 | current 层阅读入口、能力矩阵和验证基线 |

## 能力矩阵

| 能力 | 当前状态 | 事实源 |
| --- | --- | --- |
| 单根首页 | 已落地。`TimelineHomeView` 是根体验，根级任务卡片由 `RootView` 的 `.sheet(item:)` 承载。 | `RootView.swift`、`TimelineHomeView.swift` |
| 首页场景壳 | 已落地。顶部 chrome、热力图上下文槽位、筛选 half-sheet presenter、时间轴列表和 FAB 已拆成独立组合点。 | `TimelineHomeView.swift`、`TimelineHomeChromeView.swift`、`TimelineHomePresentation.swift` |
| 时间轴阅读单元 | 已落地。每行由日期列、心情节点、气泡内容组成；三者是可分别调样式的对象，但左滑删除的视觉目标是这一整条阅读单元。 | `TimelineGeometry.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`MoodNodeView.swift`、`BubbleCardView.swift` |
| 时间轴连续性 | 已落地。连续轨道由 `TimelineRailSceneLayer` 承载在 `TimelineViewportView` 场景层；阅读单元位于行前景。轨道坐标、首屏标题槽位、底部超出、滚动相位和可见性均已收口到专门类型。 | `TimelineViewportMetrics.swift`、`TimelineRailVisibility.swift`、`TimelineRailSceneLayer.swift` |
| 热力图定位 | 已落地。热力图作为首页局部状态原位展开；点日/点有记录的月份只写时间 anchor，不改筛选条件。 | `TimelineHomeView.swift`、`YearHeatmapView.swift`、`HeatmapGridView.swift` |
| 筛选 | 已落地。首页局部半屏/大屏 `FilterPanelView` sheet，不进 `AppRouter.rootSheet`；标签/心情选择即时生效，提供“全部心情”和“清除全部”。 | `TimelineHomeView.swift`、`FilterPanelView.swift` |
| 标签创建归属 | 已落地。编辑器和筛选只消费已有标签；标签新增、重命名、删除统一归属设置页 `TagManageView`。 | `MomentEditorView.swift`、`TagPickerView.swift`、`FilterPanelView.swift`、`TagManageView.swift` |
| 数据持久化 | 已落地。生产主 UI、用户写入、本机恢复点、Markdown/PDF 导出和 UI 测试种子均使用 GRDB canonical store；Moment 原图由 `FileAssetStore` 管理。同步状态仍是启发式展示，不代表 canonical iCloud 同步已经完成。 | `MoodmentsApp.swift`、`RootView.swift`、`CanonicalLibraryService.swift`、`LocalLibraryMutationService.swift`、`CanonicalStore.swift`、`CanonicalLibraryRuntime.swift`、`FileAssetStore.swift`、`CanonicalLibraryRepository.swift` |
| 本地自动恢复点 | 已落地。设置页“备份与恢复”使用 `CanonicalBackupRestoreService`；最多展示 3 个系统自动维护的本机恢复点，用户可预览并准备恢复，不能删除、分享或导出恢复点。 | `BackupRestoreService.swift`、`BackupRestoreView.swift`、`PendingLocalRestoreView.swift`、`CanonicalRecoveryCoordinator.swift`、`CanonicalRestoreExecutor.swift`、`CanonicalBootRestoreGate.swift` |
| Markdown / PDF 导出 | 已落地。设置页“导出”详情页可导出全部活跃 Moment 为 Markdown 或 PDF；导出只读，不改变 canonical store，不创建恢复点，不参与 iCloud 同步。 | `ExportService.swift`、`MarkdownExportRenderer.swift`、`PDFExportRenderer.swift`、`ExportView.swift` |
| Canonical 恢复点地基 | 已落地并接入生产设置页和启动路径。catalog、asset manifest、content-hash pin、真实 SQLite snapshot、stage/arm/boot replace/rollback 和 migration safety gate 均已有定向测试。 | `CanonicalRecoveryPointStore.swift`、`CanonicalRecoveryPointSnapshotService.swift`、`CanonicalRecoveryCoordinator.swift`、`CanonicalRestoreExecutor.swift`、`CanonicalBootRestoreGate.swift`、`CanonicalMigrationSafetyGate.swift` |
| 编辑页日期/时间选择 | 已落地。日期和时间由局部 `.popover` 打开系统 `DatePicker`，即时回写 `occurredAt`。 | `MomentEditorView.swift`、`DateTimePopovers.swift` |
| 任务页骨架 | 已落地。设置、外观、编辑、预览、Paywall、筛选和标签创建等 sheet 共享 `AppSheetScaffold` / `AppSheetActionButton` / `TaskSurfaceMetrics` / `TaskPageScrollView` 等骨架；半屏筛选仍保留自身 detent 和即时筛选语义。 | `AppSheetScaffold.swift`、`AppSheetNavigationChrome.swift`、`TaskContainerStyle.swift`、`SettingsSheetView.swift`、`MomentEditorView.swift`、`FilterPanelView.swift`、`TagCreateSheetView.swift` |
| 设置流 | 已落地。设置页是第一层 sheet，详情页在设置内 `NavigationStack` push 并保留系统返回；根页和详情页通过 `AppSheetNavigationChrome` 统一。 | `SettingsSheetView.swift`、`AppSheetNavigationChrome.swift` |
| 外观设置 | 部分落地。模式、主色、网格、图片展示已有 UI、持久化和消费路径；自定义背景图是本地外观文件，不进入 canonical 资料库或 CloudKit。 | `AppearanceThemeView.swift`、`AppearanceOptionCards.swift`、`ThemeManager.swift`、`AppearanceStore.swift` |
| 主题语义 | 已落地。主色、心情色、危险色、商业固定色和图片查看器媒体色由不同语义入口暴露，心情色、危险色、商业固定色不跟随主色。 | `ThemeManager.swift`、`ThemeTokens.swift`、`Colors.swift` |

## 当前验证基线

脚本与测试入口已收口到 [`../../scripts/README.md`](../../scripts/README.md) 描述的三层模型：`dev.sh` 是日常门面，`test.sh` 是 XCTest/XCUITest 统一入口，`verify.sh` 是本地与 CI 共用的一条龙验证入口。测试数据隔离和 UI launch arguments 的 current 契约见 [`testing-architecture.md`](testing-architecture.md)。

与本 current 相关的已有测试面包括：

- `Tests/MoodmentsTests/CanonicalStoreTests.swift`
- `Tests/MoodmentsTests/CanonicalRepositoryParityTests.swift`
- `Tests/MoodmentsTests/CanonicalLibraryServiceTests.swift`
- `Tests/MoodmentsTests/LocalLibraryMutationServiceTests.swift`
- `Tests/MoodmentsTests/LocalDataClosureAcceptanceTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryPointSchemaTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryPointStoreTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryPointSnapshotServiceTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryCoordinatorTests.swift`
- `Tests/MoodmentsTests/CanonicalRestoreExecutorTests.swift`
- `Tests/MoodmentsTests/CanonicalBootRestoreGateTests.swift`
- `Tests/MoodmentsTests/CanonicalMigrationSafetyGateTests.swift`
- `Tests/MoodmentsTests/BackupRestoreServiceTests.swift`
- `Tests/MoodmentsTests/FileAssetStoreTests.swift`
- `Tests/MoodmentsTests/CanonicalAssetReachabilityServiceTests.swift`
- `Tests/MoodmentsTests/CanonicalAssetPinSchemaTests.swift`
- `Tests/MoodmentsTests/CanonicalAssetPinStoreTests.swift`
- `Tests/MoodmentsTests/MarkdownExportServiceTests.swift`
- `Tests/MoodmentsTests/PDFExportServiceTests.swift`
- `Tests/MoodmentsTests/MarkdownExportRendererTests.swift`
- `Tests/MoodmentsTests/PDFExportRendererTests.swift`
- `Tests/MoodmentsTests/DefaultTagSeederTests.swift`
- `Tests/MoodmentsTests/LocateVsFilterTests.swift`
- `Tests/MoodmentsTests/HeatmapMoodColorTests.swift`
- `Tests/MoodmentsTests/MomentOccurredAtOrderingTests.swift`
- `Tests/MoodmentsTests/MomentQuotaReleaseTests.swift`
- `Tests/MoodmentsTests/MomentRestoreOrderingTests.swift`
- `Tests/MoodmentsTests/ThumbnailCacheInvalidationTests.swift`
- `Tests/MoodmentsUITests/BackupRestoreUITests.swift`
- `Tests/MoodmentsUITests/MarkdownExportUITests.swift`
- `Tests/MoodmentsUITests/DeleteRestorePurgeUITests.swift`

2026-07-11 本轮架构清理验证：

```bash
./scripts/gen.sh
./scripts/test.sh --unit
```

结果：通过。`./scripts/test.sh --unit` 执行 266 条单元测试，4 条 skipped，0 失败。该轮清理删除旧本地存储源码、旧 repository / 旧恢复点测试和旧导入标记，保留并改造产品公理测试到 canonical repository：删除生命周期额度、发生时间排序、恢复位置、默认标签、筛选聚合、热力图、UI 写入边界、恢复点服务映射。
