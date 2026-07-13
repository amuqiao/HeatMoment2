# 当前实现真相

本文是 SwiftUI 版 HeatMoment 的 current 入口，只记录当前代码已经落地的事实、已知偏离、已实现能力边界和验证基线。产品公理以 [`../product-mental-model.md`](../product-mental-model.md) 为准；未来计划进入 [`../plans/`](../plans/README.md)。

## 文档边界

`current` 回答“现在实际怎么实现”。它不承诺未来优化，不替代计划层，也不把 Flutter 版实现细节当作 SwiftUI 事实。当前数据权威是 `Canonical Repository + GRDB + SQLite + FileAssetStore`。

| 文件 | 职责 |
| --- | --- |
| [`implementation-truth.md`](implementation-truth.md) | SwiftUI 版当前 as-built 架构、界面流、主题/时间轴/设置等落地事实与偏离 |
| [`local-data-architecture.md`](local-data-architecture.md) | 本地 canonical store、恢复点、导出和未来 iCloud 接入边界的开发者导览 |
| [`sheet-system.md`](sheet-system.md) | 当前任务 sheet 骨架、顶部动作入口、内容容器边界和最小回归测试导览 |
| [`testing-architecture.md`](testing-architecture.md) | 当前 XCTest/XCUITest 入口、数据隔离、UI 测试 launch arguments 与维护边界 |
| [`swiftui-foundation.md`](swiftui-foundation.md) | 当前 SwiftUI 小应用骨架、目录边界、能力接入和复用方式 |
| 本文 | current 层阅读入口、能力矩阵和验证基线 |

## 能力矩阵

| 能力 | 当前状态 | 事实源 |
| --- | --- | --- |
| App shell | 已落地。`RootView` 已拆成 root scene、根级任务 sheet 呈现策略和 app readiness；`AppRouter` 只保留当前真实使用的 `rootSheet` 与 `isLocked`，不保留空 push path 或无写入方 fullScreen path。 | `RootView.swift`、`AppRouter.swift` |
| 单根首页 | 已落地。`TimelineHomeView` 是根体验，根级任务卡片由 `RootView` 的 `.sheet(item:)` 承载；图片查看器由 `MomentPreviewView` 局部 `.fullScreenCover(item:)` 呈现。 | `RootView.swift`、`TimelineHomeView.swift`、`MomentPreviewView.swift` |
| 首页场景壳 | 已落地。顶部 chrome、热力图上下文槽位、筛选 half-sheet presenter、时间轴列表和 FAB 已拆成独立组合点。 | `TimelineHomeView.swift`、`TimelineHomeChromeView.swift`、`TimelineHomePresentation.swift` |
| 时间轴阅读单元 | 已落地。每行由日期列、心情节点、气泡内容组成；三者是可分别调样式的对象，但左滑删除的视觉目标是这一整条阅读单元。 | `TimelineGeometry.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`MoodNodeView.swift`、`BubbleCardView.swift` |
| 时间轴连续性 | 已落地。连续轨道由 `TimelineRailSceneLayer` 承载在 `TimelineViewportView` 场景层；阅读单元位于行前景。轨道坐标、首屏标题槽位、底部超出、滚动相位和可见性均已收口到专门类型。 | `TimelineViewportMetrics.swift`、`TimelineRailVisibility.swift`、`TimelineRailSceneLayer.swift` |
| 热力图定位 | 已落地。热力图作为首页局部状态原位展开；点日/点有记录的月份只写时间 anchor，不改筛选条件。 | `TimelineHomeView.swift`、`YearHeatmapView.swift`、`HeatmapGridView.swift` |
| 筛选 | 已落地。首页局部半屏/大屏 `FilterPanelView` sheet，不进 `AppRouter.rootSheet`；标签/心情选择即时生效，提供“全部心情”和“清除全部”。 | `TimelineHomeView.swift`、`FilterPanelView.swift` |
| 标签创建归属 | 已落地。编辑器和筛选只消费已有标签；标签新增、重命名、删除统一归属设置页 `TagManageView`。 | `MomentEditorView.swift`、`TagPickerView.swift`、`FilterPanelView.swift`、`TagManageView.swift` |
| 数据持久化 | 已落地。生产主 UI、用户写入、完整备份包、本机安全点、Markdown/PDF 阅读副本导出和 UI 测试种子均使用 GRDB canonical store；Moment 原图由 `FileAssetStore` 管理。同步状态仍是启发式展示，不代表 canonical iCloud 同步已经完成。 | `HeatMomentApp.swift`、`RootView.swift`、`CanonicalLibraryService.swift`、`LocalLibraryMutationService.swift`、`CanonicalStore.swift`、`CanonicalLibraryRuntime.swift`、`FileAssetStore.swift`、`CanonicalLibraryRepository.swift` |
| 完整备份包与恢复 | 已落地。设置页“备份与恢复”默认展示用户可携带的 `.heatmomentbackup` 完整备份包能力；导出先生成临时完整包并直接打开系统分享/保存，只有系统完成回调后才记录上次备份，取消或重新进入页面会清理临时包；导入先复制到 staging、校验 manifest / SQLite catalog / payload hash，再预览并确认整库替换。 | `BackupRestoreView.swift`、`Services/BackupPackage/BackupPackageTypes.swift`、`BackupPackageArchive.swift`、`CanonicalBackupPackageService.swift`、`CanonicalRestoreExecutor.swift`、`CanonicalBootRestoreGate.swift` |
| 本机安全点 | 已落地。内部 recovery point 机制继续维护最近 3 个 SQLite snapshot，用于高风险写入前安全点、稳定变更安全点、迁移安全点和完整备份导入前 restore-safety；不再作为设置页主备份模型展示，也不能删除、分享或导出为备份包。 | `Services/Backup/BackupRestoreService.swift`、`PendingLocalRestoreView.swift`、`CanonicalRecoveryCoordinator.swift`、`CanonicalRecoveryPointSnapshotService.swift`、`CanonicalRestoreExecutor.swift` |
| Markdown / PDF 阅读副本导出 | 已落地。设置页“阅读副本导出”详情页只消费 `ExportServicing`，生产由 App composition 注入 `CanonicalExportService`；按日期范围导出 active Moment 为 Markdown 或 PDF，导出成功后生成 share transaction 并立即打开系统分享，分享完成或取消后结束事务并清理临时副本，不改变 canonical store，不创建恢复点，不参与 iCloud 同步。 | `ExportService.swift`、`CanonicalExportSnapshotStore.swift`、`MarkdownExportRenderer.swift`、`PDFExportRenderer.swift`、`ExportView.swift` |
| 编辑页日期/时间选择 | 已落地。日期和时间由局部 `.popover` 打开系统 `DatePicker`，即时回写 `occurredAt`。 | `MomentEditorView.swift`、`DateTimePopovers.swift` |
| 任务页骨架 | 已落地。设置、外观、编辑、预览、Paywall、筛选和标签创建等 sheet 共享 `AppSheetScaffold` / `AppSheetActionButton` / `TaskSurfaceMetrics` / `TaskPageScrollView` 等骨架；半屏筛选仍保留自身 detent 和即时筛选语义。维护入口见 [`sheet-system.md`](sheet-system.md)。 | `AppSheetScaffold.swift`、`AppSheetNavigationChrome.swift`、`TaskContainerStyle.swift`、`SettingsSheetView.swift`、`MomentEditorView.swift`、`FilterPanelView.swift`、`TagCreateSheetView.swift` |
| Foundation UI 边界 | 已落地。`DesignSystem` 只保留基础 sheet/container/theme/typography/appearance/swipe 能力；心情节点、时间轴气泡、热力图、统计条、首页背景、顶部按钮、FAB、缩略图条和心情色业务 palette 已归入对应 `Features/*`。 | `DesignSystem/`、`Features/Timeline/`、`Features/Heatmap/`、`Features/Stats/`、`Features/MomentMedia/`、`Features/Mood/MoodPalette.swift` |
| 设置流 | 已落地。设置页是第一层 sheet，根页按个人化、数据与安全、管理、权益与关于分组；详情页在设置内 `NavigationStack` push 并保留系统返回；“数据与 iCloud”只展示系统 iCloud/同步状态，不表达 App 登录。 | `SettingsSheetView.swift`、`AppSheetNavigationChrome.swift` |
| SwiftUI 小应用骨架 | 已落地。当前 App composition、Foundation UI、capability contract、HeatMoment business feature 和 infrastructure 的依赖方向已沉淀为可复用维护说明。 | [`swiftui-foundation.md`](swiftui-foundation.md)、`RootView.swift`、`DesignSystem/`、`Services/`、`Features/` |
| 外观设置 | 部分落地。模式、主色、网格、图片展示已有 UI、持久化和消费路径；自定义背景图是本地外观文件，不进入 canonical 资料库或 CloudKit。 | `AppearanceThemeView.swift`、`AppearanceOptionCards.swift`、`ThemeManager.swift`、`AppearanceStore.swift` |
| 主题语义 | 已落地。基础主题 token 和 HeatMoment 心情色业务 palette 已拆开；主色、危险色、商业固定色和图片查看器媒体色由基础主题入口暴露，心情色由 `MoodPalette` 暴露且不跟随主色。 | `ThemeManager.swift`、`ThemeTokens.swift`、`Colors.swift`、`MoodPalette.swift` |

## 当前验证基线

脚本与测试入口已收口到 [`../../scripts/README.md`](../../scripts/README.md) 描述的三层模型：`dev.sh` 是日常门面，`test.sh` 是 XCTest/XCUITest 统一入口，`verify.sh` 是本地与 CI 共用的一条龙验证入口。测试数据隔离和 UI launch arguments 的 current 契约见 [`testing-architecture.md`](testing-architecture.md)。

与本 current 相关的已有测试面包括：

- `Tests/HeatMomentTests/CanonicalStoreTests.swift`
- `Tests/HeatMomentTests/CanonicalRepositoryParityTests.swift`
- `Tests/HeatMomentTests/CanonicalLibraryServiceTests.swift`
- `Tests/HeatMomentTests/LocalLibraryMutationServiceTests.swift`
- `Tests/HeatMomentTests/LocalDataClosureAcceptanceTests.swift`
- `Tests/HeatMomentTests/CanonicalRecoveryPointSchemaTests.swift`
- `Tests/HeatMomentTests/CanonicalRecoveryPointStoreTests.swift`
- `Tests/HeatMomentTests/CanonicalRecoveryPointSnapshotServiceTests.swift`
- `Tests/HeatMomentTests/CanonicalRecoveryCoordinatorTests.swift`
- `Tests/HeatMomentTests/CanonicalRestoreExecutorTests.swift`
- `Tests/HeatMomentTests/CanonicalBootRestoreGateTests.swift`
- `Tests/HeatMomentTests/CanonicalMigrationSafetyGateTests.swift`
- `Tests/HeatMomentTests/BackupPackageServiceTests.swift`
- `Tests/HeatMomentTests/BackupRestoreServiceTests.swift`
- `Tests/HeatMomentTests/FileAssetStoreTests.swift`
- `Tests/HeatMomentTests/CanonicalAssetReachabilityServiceTests.swift`
- `Tests/HeatMomentTests/CanonicalAssetPinSchemaTests.swift`
- `Tests/HeatMomentTests/CanonicalAssetPinStoreTests.swift`
- `Tests/HeatMomentTests/MarkdownExportServiceTests.swift`
- `Tests/HeatMomentTests/PDFExportServiceTests.swift`
- `Tests/HeatMomentTests/MarkdownExportRendererTests.swift`
- `Tests/HeatMomentTests/PDFExportRendererTests.swift`
- `Tests/HeatMomentTests/DefaultTagSeederTests.swift`
- `Tests/HeatMomentTests/LocateVsFilterTests.swift`
- `Tests/HeatMomentTests/HeatmapMoodColorTests.swift`
- `Tests/HeatMomentTests/MomentOccurredAtOrderingTests.swift`
- `Tests/HeatMomentTests/MomentQuotaReleaseTests.swift`
- `Tests/HeatMomentTests/MomentRestoreOrderingTests.swift`
- `Tests/HeatMomentTests/ThumbnailCacheInvalidationTests.swift`
- `Tests/HeatMomentUITests/BackupRestoreUITests.swift`
- `Tests/HeatMomentUITests/MarkdownExportUITests.swift`
- `Tests/HeatMomentUITests/DeleteRestorePurgeUITests.swift`

2026-07-11 本轮架构清理验证：

```bash
./scripts/gen.sh
./scripts/test.sh --unit
```

结果：通过。`./scripts/test.sh --unit` 执行 266 条单元测试，4 条 skipped，0 失败；覆盖 canonical repository、删除生命周期额度、发生时间排序、恢复位置、默认标签、筛选聚合、热力图、UI 写入边界和恢复点服务映射。

2026-07-13 完整备份包与恢复定向验证：

```bash
./scripts/build.sh
./scripts/test.sh --only HeatMomentTests/BackupPackageServiceTests
./scripts/test.sh --only HeatMomentUITests/BackupRestoreUITests
```

结果：通过。`BackupPackageServiceTests` 执行 12 个测试、0 失败，覆盖临时完整包准备/预览、准备后不记录上次备份、系统完成提交后记录并清理、清理失败时仍保留已完成记录并返回 cleanup 状态、取消后不记录并清理、摘要读取不销毁 active 准备态、显式清理遗留临时包、尾部篡改拒绝、payload hash 篡改拒绝与 staging 清理、跨 runtime 导入 staging、pending restore arm、保留策略失败后的 armed restore 结果、冷启动整库替换和照片恢复。`BackupRestoreUITests` 执行 1 个测试、0 失败，覆盖设置页极简完整备份入口、旧恢复点 UI 和旧二步导出结果区不再展示。
