# 当前实现真相

本文是 SwiftUI 版 Moodments 的 current 入口，只记录当前代码已经落地的事实、已知偏离和验证基线。产品公理以 [`../product-mental-model.md`](../product-mental-model.md) 为准；数据生命周期、备份、恢复、导出和 iCloud 同步的目标架构进入 [`../plans/implementation-plan.md`](../plans/implementation-plan.md)。

## 文档边界

`current` 回答“现在实际怎么实现”。它不承诺未来优化，不替代计划层，也不把 Flutter 版实现细节当作 SwiftUI 事实。当前 SwiftData 路径是已实现事实和过渡实现，不是目标架构里的最终数据权威。

| 文件 | 职责 |
| --- | --- |
| [`implementation-truth.md`](implementation-truth.md) | SwiftUI 版当前 as-built 架构、界面流、主题/时间轴/设置等落地事实与偏离 |
| [`testing-architecture.md`](testing-architecture.md) | 当前 XCTest/XCUITest 入口、数据隔离、UI 测试 launch arguments 与维护边界 |
| 本文 | current 层阅读入口、能力矩阵和验证基线 |

## 能力矩阵

| 能力 | 当前状态 | 事实源 |
| --- | --- | --- |
| 单根首页 | 已落地。`TimelineHomeView` 是根体验，根级任务卡片由 `RootView` 的 `.sheet(item:)` 承载。 | `Sources/Moodments/App/RootView.swift`、`Sources/Moodments/Features/Timeline/TimelineHomeView.swift` |
| 首页场景壳 | 已落地。顶部 chrome、热力图上下文槽位、筛选 half-sheet presenter、时间轴列表和 FAB 已拆成独立组合点。 | `TimelineHomeView.swift`、`TimelineHomeChromeView.swift`、`TimelineHomePresentation.swift` |
| 时间轴阅读单元 | 已落地。每行由日期列、心情节点、气泡内容组成；三者是可分别调样式的对象，但左滑删除的视觉目标是这一整条阅读单元。位置、节点锚点和气泡尾巴几何由 `TimelineGeometry` 集中定义，方便后续移动时间轴、锚定节点和调整气泡尾巴。 | `TimelineGeometry.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`MoodNodeView.swift`、`BubbleCardView.swift` |
| 时间轴连续性 | 结构归属已调整。连续轨道由 `TimelineRailSceneLayer` 承载在 `TimelineViewportView` 场景层，不属于任何 `List` row；阅读单元位于行前景。轨道 x、节点中心、日期列和气泡尾巴关系由 `TimelineGeometry` 集中定义；首屏标题槽位、标题到轨道顶点间隔和底部超出由 `TimelineViewportLayout` 定义；滚动相位和 viewport bounds 由 `TimelineViewportMetrics` 计算。轨道不再依赖 `List` 行 preference 上报后才渲染。轨道可见性由 `TimelineRailVisibility` 收口，只有存在阅读单元时才渲染，筛选空态不留下孤立轨道。滚动宿主使用 SwiftUI `List`，删除使用系统 `.swipeActions(allowsFullSwipe: true)`，支持轻扫露出按钮和继续滑动触发删除；真实 Moment 的 VoiceOver 默认动作打开预览，删除作为命名动作保留。定向单元测试已锁住节点中心与轨道坐标合同。 | `TimelineGeometry.swift`、`TimelineViewportMetrics.swift`、`TimelineRailVisibility.swift`、`TimelineRailSceneLayer.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`BubbleCardView.swift` |
| 热力图定位 | 已落地。热力图由首页局部状态在导航栏下方原位展开，作为顶部上下文区参与主页布局；点日/点有记录的月份只写时间 anchor，不改筛选条件。选中月份用主色低透明蒙层标记。 | `TimelineHomeView.swift`、`YearHeatmapView.swift`、`HeatmapGridView.swift`、`TimelineViewportView.swift` |
| 筛选 | 已落地。当前是首页局部半屏/大屏 `FilterPanelView` sheet，不进 `AppRouter.rootSheet`，标签/心情以紧凑网格选择，提供“全部心情”和“清除全部”，点选即时生效且选择后不自动关闭；筛选 sheet 只选择已有标签，不提供标签新增入口。 | `TimelineHomeView.swift`、`FilterPanelView.swift` |
| 标签创建归属 | 已落地。编辑器 `TagPickerView` 和首页筛选 `FilterPanelView` 只消费已有标签，不临时创建标签；标签新增、重命名、删除统一归属设置页 `TagManageView`。 | `MomentEditorView.swift`、`TagPickerView.swift`、`FilterPanelView.swift`、`TagManageView.swift` |
| 数据持久化 | M2 主 UI runtime cutover 已落地。`MoodmentsApp` 现在创建并注入 `CanonicalLibraryService` / `CanonicalLibraryRuntime`，`RootView` 在进入主页前执行一次 SwiftData -> canonical baseline 导入；时间轴、筛选、预览、编辑、标签管理、垃圾箱、统计/热力图、缩略图原图读取和主流程写入已改为消费 canonical 值类型与 `changeToken`。`LocalLibraryMutationService` 生产主流程委托 `CanonicalLibraryRepository`，SwiftData backend 仅保留给尚未迁移的测试/过渡调用方。App 仍创建 SwiftData `ModelContainer`，用于 baseline 导入以及 M3/M4 前的恢复点、导出和部分测试种子；同步状态仍是启发式展示，不代表 canonical iCloud 同步已经完成。 | `ModelContainer+Config.swift`、`MoodmentsApp.swift`、`RootView.swift`、`CanonicalLibraryService.swift`、`LocalLibraryMutationService.swift`、`SyncStatusService.swift`、`CanonicalStore.swift`、`CanonicalLibraryRuntime.swift`、`FileAssetStore.swift`、`SwiftDataCanonicalImporter.swift`、`CanonicalLibraryRepository.swift` |
| 本地自动恢复点 | SwiftData 过渡版恢复服务仍存在于代码和测试中，但 M2 后不再作为用户可触达的生产恢复入口：设置页“备份与恢复”行显示为暂不可用占位，避免用户看到不覆盖 canonical 新写入的旧恢复点。非 CloudKit SwiftData 容器下，旧路径仍能维护最多 3 个恢复点；canonical backend 当前不会创建 SwiftData 稳定恢复点或安全点。canonical recovery catalog / coordinator / boot restore gate 已有内部能力，尚未接到设置页和普通生产启动；因此 M3 完成前，不能把“本地备份与恢复”声明为 canonical 闭环。 | `SettingsSheetView.swift`、`LocalLibraryMutationService.swift`、`LocalBackupCoordinator.swift`、`RecoveryPointManager.swift`、`LocalBackupRestoreExecutor.swift`、`BackupRestoreService.swift`、`BackupRestoreView.swift`、`PendingLocalRestoreView.swift`、`CanonicalRecoveryCoordinator.swift`、`CanonicalBootRestoreGate.swift` |
| Markdown / PDF 导出 | 已落地 SwiftData 过渡版 M1。设置页“导出”详情页可选择 Markdown 或 PDF，但当前 snapshot source 仍读取 SwiftData 活跃 Moment；M2 后 canonical 新写入不会自动进入该 SwiftData 导出源。Markdown / PDF renderer 和分享行为已可复用，M4 需要把 snapshot source 切到 canonical / `FileAssetStore` 后才算与主 UI 同源。当前只支持全部活跃时刻，不支持筛选/日期范围/持久导出任务。 | `ExportService.swift`、`MarkdownExportRenderer.swift`、`PDFExportRenderer.swift`、`ExportView.swift` |
| Canonical 恢复点地基 | 已落地内部 store/snapshot/coordinator/executor/boot gate/migration gate，尚未接生产设置页。v4 schema 新增 `recovery_point_record` 与 `recovery_point_asset_record`，记录恢复点原因、状态、schema/app version、source library、SQLite 快照相对路径/字节数/hash、记录/标签/照片计数和 asset manifest；`CanonicalRecoveryPointStore` 在单个 GRDB 写事务内创建 catalog、写入 asset manifest、写入 `owner_kind = recoveryPoint` 的 content-hash pin，并在超过 3 个时淘汰最旧恢复点和释放对应 pin；内部也支持暂缓 retention、显式执行 retention 和删除单个恢复点。`CanonicalRecoveryCoordinator` 已提供列表、当前 counts、稳定变更节流恢复点、mutation safety 恢复点、恢复点校验、兼容性检查和 prepare restore；`CanonicalRestoreExecutor` / `CanonicalBootRestoreGate` 已提供 stage / arm / boot replace / rollback 路径。当前还没有设置页 canonical 恢复点生产 UI，也没有把普通 SwiftUI 启动切成先消费 canonical pending restore 再打开 runtime。 | `CanonicalStore.swift`、`CanonicalRecords.swift`、`CanonicalRecoveryPointStore.swift`、`CanonicalRecoveryPointSnapshotService.swift`、`CanonicalRecoveryCoordinator.swift`、`CanonicalRestoreExecutor.swift`、`CanonicalBootRestoreGate.swift`、`CanonicalMigrationSafetyGate.swift`、`CanonicalLibraryRuntime.swift` |
| 上下文标记 | 已落地。筛选标记和时间定位标记可并存、可分别移除。 | `TimelineContextMarkerBar.swift`、`TimelineModel.swift` |
| 编辑页日期/时间选择 | 已落地。日期和时间由局部 `.popover` 打开系统 `DatePicker`，即时回写 `occurredAt`；日期/时间 popover 打开与 `OccurredAtComposer` 合成语义已有窄测试覆盖，时间 picker 只替换时/分并保留不可见秒。 | `MomentEditorView.swift`、`DateTimePopovers.swift` |
| 任务页骨架 | 已落地。设置、外观、编辑、预览等任务型 sheet 共享 `TaskSurfaceMetrics` / `TaskPageScrollView` / `TaskSurfaceSection` / `TaskSurfacePanel` 的响应式内容列；Pro 横幅、设置分组、外观分组、编辑输入面板和添加照片 CTA 统一横向边界。首页气泡、时间轴、筛选 popover、标签创建 sheet 不混入这套任务内容列。 | `TaskContainerStyle.swift`、`SettingsSheetView.swift`、`AppearanceThemeView.swift`、`MomentEditorView.swift`、`MomentPreviewView.swift` |
| 设置流 | 已落地。设置页是第一层 sheet，根页不提供显式关闭按钮，依赖系统 sheet 下滑关闭；子页在设置内 `NavigationStack` push 并保留系统返回。设置根页和设置详情页通过 settings-only 导航 chrome 统一使用系统导航栏：根页保留系统标题样式，详情页显式 inline 居中标题，并保留系统 scroll-edge 导航栏背景行为。设置根页内容使用任务页响应式内容列，而不是各组独立写宽度。Pro 可作为设置内第二层 sheet。标签新增、重命名、删除归属 `TagManageView`，新增入口和保存创建前都做标签额度闸门，删除使用系统 `.swipeActions(allowsFullSwipe: true)`。 | `SettingsSheetView.swift`、`SettingsNavigationChrome.swift`、`TagManageView.swift` |
| 外观设置 | 部分落地。模式、主色、网格、图片展示已有 UI、内存态、持久化和实际消费路径；`backgroundTexture` 已驱动首页主场景背景的网格线/点阵/无/自定义图片四分支，自定义图片为本地外观文件，不进入 SwiftData/CloudKit；`imageDisplayMode` 已驱动首页气泡图片区在横向缩略图布局和轮播布局之间切换；外观页使用任务页内容列和自适应分组网格，以模式总览预览、主色 swatch、纯背景纹理样本和图片展示样本表达差异，并消费真实主题 token。剩余是亮色截图审计和细节精修。 | `AppearanceThemeView.swift`、`AppearanceOptionCards.swift`、`ThemeManager.swift`、`AppearanceStore.swift`、`HomeSceneBackgroundView.swift`、`TimelineHomeView.swift`、`BubbleCardView.swift`、`ThumbnailStripView.swift` |
| 主题语义 | 已落地。`ThemeManager.tokens` 解析五层运行时 token；主色、心情色、危险色、商业固定色和图片查看器媒体色由不同语义入口暴露，心情色、危险色、商业固定色不跟随主色。 | `ThemeManager.swift`、`ThemeTokens.swift`、`Colors.swift` |

## 当前验证基线

本次 current 基线来自 P0 实现后的代码审计、定向单元测试、定向 UI 测试、构建和 lint 验证。

脚本与测试入口已收口到 [`../../scripts/README.md`](../../scripts/README.md) 描述的三层模型：`dev.sh` 是日常门面，`test.sh` 是 XCTest/XCUITest 统一入口，`verify.sh` 是本地与 CI 共用的一条龙验证入口。测试数据隔离和 UI launch arguments 的 current 契约见 [`testing-architecture.md`](testing-architecture.md)。

与本 current 相关的已有测试面包括：

- `Tests/MoodmentsTests/LocateVsFilterTests.swift`
- `Tests/MoodmentsTests/HeatmapMoodColorTests.swift`
- `Tests/MoodmentsTests/MoodPaletteTests.swift`
- `Tests/MoodmentsTests/AppearanceStoreTests.swift`
- `Tests/MoodmentsTests/MomentCardLayoutTests.swift`
- `Tests/MoodmentsTests/EditorSaveValidationTests.swift`
- `Tests/MoodmentsTests/OccurredAtComposerTests.swift`
- `Tests/MoodmentsTests/RecoveryPointManagerTests.swift`
- `Tests/MoodmentsTests/RecoveryPointManagerValidationTests.swift`
- `Tests/MoodmentsTests/LocalBackupCoordinatorTests.swift`
- `Tests/MoodmentsTests/LocalBackupRestoreExecutorTests.swift`
- `Tests/MoodmentsTests/LocalLibraryMutationServiceTests.swift`
- `Tests/MoodmentsTests/CanonicalStoreTests.swift`
- `Tests/MoodmentsTests/CanonicalRepositoryParityTests.swift`
- `Tests/MoodmentsTests/CanonicalRuntimeImportTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryPointSchemaTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryPointStoreTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryPointSnapshotServiceTests.swift`
- `Tests/MoodmentsTests/CanonicalRecoveryCoordinatorTests.swift`
- `Tests/MoodmentsTests/CanonicalRestoreExecutorTests.swift`
- `Tests/MoodmentsTests/CanonicalBootRestoreGateTests.swift`
- `Tests/MoodmentsTests/CanonicalMigrationSafetyGateTests.swift`
- `Tests/MoodmentsTests/BackupRestoreServiceTests.swift`
- `Tests/MoodmentsTests/ThumbnailCacheInvalidationTests.swift`
- `Tests/MoodmentsUITests/BackupRestoreUITests.swift`
- `Tests/MoodmentsUITests/CreateMomentFlowUITests.swift`
- `Tests/MoodmentsUITests/TitleCollapseFilterUITests.swift`
- `Tests/MoodmentsUITests/LocateFilterUITests.swift`
- `Tests/MoodmentsUITests/DeleteRestorePurgeUITests.swift`
- `Tests/MoodmentsUITests/EditorSheetPresentationUITests.swift`
- `Tests/MoodmentsUITests/TagManageUITests.swift`
- `Tests/MoodmentsUITests/ThemeSwitchUITests.swift`
- `Tests/MoodmentsUITests/AppearanceSaveFailureUITests.swift`
- `Tests/MoodmentsUITests/P0VisualAuditCaptureUITests.swift`

文档层验证命令：

```sh
rg -n "docs/current|docs/plans|implementation-truth|implementation-plan" CLAUDE.md docs
```

全量代码验证入口：

```sh
./scripts/test.sh --unit
./scripts/test.sh --ui
```

2026-07-07 本轮时间轴 / Moment 卡片骨架修正的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/TimelineGeometryTests
./scripts/test.sh --only MoodmentsTests/TimelineRailVisibilityTests
./scripts/test.sh --only MoodmentsTests/MomentCardLayoutTests
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testSwipeDeleteMovesToTrash
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testSwipingOnTimelineImageDoesNotTriggerDelete
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testSwipingOnTimelineCarouselImageDoesNotTriggerDelete
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testPreviewIsCardNotPush
./scripts/test.sh --only MoodmentsUITests/LocateFilterUITests/testFilterAbsentMoodShowsEmptyStateThenMarkerRemovalRestoresRecords
./scripts/test.sh --only MoodmentsUITests/TimelineEmptyStateUITests/testEmptyStateShowsThreeGuidedMoments
./scripts/build.sh
./scripts/lint.sh
```

结果：全部通过；`TimelineRailVisibilityTests` 锁住筛选空态不渲染孤立轨道、真实/引导阅读单元仍渲染轨道；筛选空态 UI 和未筛选引导空态 UI 均通过。`lint` 仍输出既有 warning，但本轮触碰文件没有新增未处理 warning。模拟器/真机截图层面的时间轴视觉对齐、左滑过程中轨道与阅读单元的像素级连续感仍需人工复核。

2026-07-08 本轮任务页响应式骨架重构的定向验证：

```sh
./scripts/build.sh
./scripts/test.sh --only MoodmentsUITests/EditorSheetPresentationUITests
./scripts/test.sh --only MoodmentsUITests/ThemeSwitchUITests
./scripts/test.sh --only MoodmentsUITests/AppearanceSaveFailureUITests
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests
./scripts/test.sh --only MoodmentsUITests/TagManageUITests
./scripts/verify.sh
```

结果：全部通过。最终 `./scripts/verify.sh` 覆盖 lint、build、144 条单元测试和 47 条 UI 测试；本轮重点验证设置页各任务面板同宽、外观页各分组同宽、编辑输入面板与添加照片 CTA 同宽、外观项切换和保存失败提示、预览仍为任务卡片而非 push、垃圾箱 swipe 生命周期，以及标签新增/重命名/删除集中在设置页管理。`lint` 仍输出既有非阻断 warning。

2026-07-08 本轮设置流导航 chrome 骨架稳定化的定向验证：

```sh
./scripts/gen.sh
./scripts/build.sh
./scripts/test.sh --only MoodmentsUITests/EditorSheetPresentationUITests
./scripts/test.sh --only MoodmentsUITests/ThemeSwitchUITests
./scripts/test.sh --only MoodmentsUITests/LanguageSwitchUITests
./scripts/verify.sh
```

结果：全部通过。`EditorSheetPresentationUITests` 执行 6 条 UI 测试、0 失败，覆盖设置根页无显式关闭按钮、设置详情页系统标题和系统返回路径、设置任务面板横向边界、编辑任务面板横向边界；`ThemeSwitchUITests` 执行 10 条 UI 测试、0 失败；`LanguageSwitchUITests` 执行 2 条 UI 测试、0 失败。最终 `./scripts/verify.sh` 覆盖 lint、build、144 条单元测试（4 条 skipped）和 49 条 UI 测试；`lint` 仍输出既有非阻断 warning。

2026-07-10 本轮本地备份恢复闭环的定向验证：

```sh
./scripts/gen.sh
./scripts/lint.sh
./scripts/test.sh --only MoodmentsTests/LocalBackupRestoreExecutorTests
./scripts/test.sh --only MoodmentsUITests/BackupRestoreUITests/testBackupListShowsSystemMaintainedRecoveryPointAndPreview
./scripts/test.sh --only MoodmentsUITests/BackupRestoreUITests/testPreparedRestoreRunsOnNextLaunchAndShowsSuccess
```

结果：全部通过。`LocalBackupRestoreExecutorTests` 覆盖 pending restore staging、armed marker、恢复前安全点、恢复点淘汰后仍能从 staged payload 恢复、损坏 pending payload 不替换当前 store。`BackupRestoreUITests` 使用磁盘隔离本地容器覆盖恢复点列表不可删除、恢复预览、准备恢复后的阻断页、终止并冷启动后的 replace restore 成功提示，以及恢复后当前资料库内容被所选恢复点替换。`lint` 仍输出既有非阻断 warning。

2026-07-10 本轮 canonical local core 骨架的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalStoreTests
```

结果：全部通过。`CanonicalStoreTests` 覆盖 GRDB schema migration、现有 store 重开后 metadata 稳定、Moment 创建/软删/恢复/彻底删除进入 `purgePending` 的查询状态与 mutation log、缺失标签时 create/update 事务回滚、多标签稳定排序、标签 create-or-reuse/额度/rename/delete、删除被引用标签时 moment revision 与 mutation 同步、tag tombstone、重名 rename 不产生部分写入，以及 asset link 的排序唯一约束。本轮未切换生产 UI；SwiftData 仍是当前用户路径。

2026-07-10 本轮 canonical runtime 与 SwiftData baseline 导入器的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalRuntimeImportTests
```

结果：全部通过。`CanonicalRuntimeImportTests` 覆盖 runtime 落盘建库、SwiftData active/softDeleted Moment、Tag、Image baseline 导入、导入完成标记与 source fingerprint、重复导入跳过、source mismatch 拒绝、异常源数据回滚、非空 canonical 目标或仅有历史表内容时拒绝导入，以及 baseline 导入不写 mutation log。本轮仍未切换生产 UI；SwiftData 仍是当前用户路径。

2026-07-10 本轮 canonical asset store 地基的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/FileAssetStoreTests
./scripts/test.sh --only MoodmentsTests/CanonicalRuntimeImportTests
```

结果：全部通过。`FileAssetStoreTests` 覆盖 content-addressed 原图写入、按 hash 读回、相同 bytes 去重，以及 expected hash mismatch 快速失败且不产生 blob；`CanonicalRuntimeImportTests` 扩展覆盖 SwiftData baseline 导入后 `asset_record.content_hash` 与真实 asset store 文件一致、两个相同原图只落一个 content-addressed blob。该轮尚未实现 asset pin、reachability audit、GC、canonical recovery catalog 或导出任务。

2026-07-10 本轮 canonical asset reachability / orphan cleanup 的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalAssetReachabilityServiceTests
./scripts/test.sh --only MoodmentsTests/FileAssetStoreTests
./scripts/test.sh --only MoodmentsTests/CanonicalRuntimeImportTests
```

结果：全部通过。`CanonicalAssetReachabilityServiceTests` 覆盖 linked asset clean audit、DB 无引用 orphan blob 清理、共享 `content_hash` 时不误删 blob、无 link asset record 报告、DB 引用 blob 缺失报告、invalid DB hash、invalid stored path、corrupt blob、同一 asset root 的 runtime 共享 operation gate，以及存在 blocking issue 时阻断 cleanup。`FileAssetStoreTests` 额外覆盖新增 list / validate / remove blob API。当前 cleanup 与 SwiftData baseline import 按标准化 asset root 路径共享 `CanonicalAssetOperationGate`，只删除 DB 无引用的 orphan blob，不自动删除 `asset_record`，也不是完整 asset GC；recovery/export/sync pin 仍未实现。

2026-07-10 本轮 canonical asset GC dry-run / DB orphan record finalizer 的定向验证：

```sh
./scripts/test.sh --only MoodmentsTests/CanonicalAssetReachabilityServiceTests
```

结果：通过。`CanonicalAssetReachabilityServiceTests` 扩展到 16 个用例，覆盖 GC dry-run plan、当前 orphan blob 候选、finalize unlinked + unpinned `asset_record`、共享 `content_hash` 时只删无用 record 且保留 blob、pinned unlinked record 保留、negative `pin_count` 作为 blocking issue 报告，以及 blocking issue 阻断 finalizer。当前 finalizer 只删除 DB 中无 link 且 `pin_count == 0` 的 `asset_record`，不删除 blob；blob 删除仍走受保护 orphan cleanup。完整 recovery/export/sync pin 表和自动 GC 调度仍未实现。

2026-07-10 本轮 canonical content-hash pin / pin-aware GC planner 的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalAssetPinSchemaTests
./scripts/test.sh --only MoodmentsTests/CanonicalAssetPinStoreTests
./scripts/test.sh --only MoodmentsTests/CanonicalAssetReachabilityServiceTests
./scripts/build.sh
./scripts/lint.sh
git diff --check
```

结果：通过。`CanonicalAssetPinSchemaTests` 覆盖 fresh schema 和 v2 -> v3 upgrade 的 `asset_pin_record` 表、`asset_record.content_hash` 索引和 pin 表索引；`CanonicalAssetPinStoreTests` 覆盖 content-hash pin upsert、release、invalid hash、empty owner 和 invalid expiration 快速失败；`CanonicalAssetReachabilityServiceTests` 扩展到 22 个用例，覆盖 active pin 保护当前 orphan blob、active pin 保护 finalizable record 对应 blob、active pin 保护对象缺失 blob 作为 blocking issue、expired pin 不再保护、invalid pin hash / invalid pin expiration 作为 blocking issue。`./scripts/lint.sh` 退出码为 0，但仓库仍有既有 warning。当前 pin 表是 content-hash lease 地基，尚未接入 recovery catalog、restore staging、export job 或 sync job 的真实创建/释放流程，也还没有完整 GC 执行入口。

2026-07-10 本轮 canonical recovery point catalog / asset manifest / recoveryPoint pin 生命周期的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalRecoveryPointSchemaTests
./scripts/test.sh --only MoodmentsTests/CanonicalRecoveryPointStoreTests
./scripts/test.sh --only MoodmentsTests/CanonicalRecoveryPointValidationTests
./scripts/test.sh --only MoodmentsTests/CanonicalAssetPinSchemaTests
./scripts/build.sh
./scripts/lint.sh
git diff --check
```

结果：通过。`CanonicalRecoveryPointSchemaTests` 覆盖 fresh schema 和 v3 -> v4 upgrade 的 `recovery_point_record`、`recovery_point_asset_record` 与索引；`CanonicalRecoveryPointStoreTests` 覆盖创建恢复点时写 catalog、asset manifest、recoveryPoint content-hash pin，超过 3 个恢复点时淘汰最旧项并释放对应 pin，且不会删除同 hash 的其他 owner pin；`CanonicalRecoveryPointValidationTests` 覆盖非法 app version、snapshot path、负计数、asset count mismatch、invalid asset hash、重复 asset ID 在写入前快速失败。`CanonicalAssetPinSchemaTests` 已更新为 v2 store 重新应用 v3/v4 的迁移场景。`./scripts/lint.sh` 退出码为 0，但仓库仍有既有 warning，本阶段新增文件也有非阻断 complexity / file length / formatter warning，留待统一 lint 规则整理或后续小步拆分。当前只完成 canonical 内部恢复点目录、资产清单和 pin 生命周期地基；真实 SQLite 快照文件创建、恢复点完整性校验 UI、restore staging、canonical replace restore、导出和 iCloud 同步仍未实现。

2026-07-10 本轮 canonical recovery point 真实 SQLite snapshot / 校验的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/RecoveryPointSnapshotServiceTests
./scripts/test.sh --only MoodmentsTests/CanonicalRecoveryPointStoreTests
./scripts/test.sh --only MoodmentsTests/CanonicalRecoveryPointValidationTests
./scripts/build.sh
./scripts/lint.sh
git diff --check
```

结果：通过。`RecoveryPointSnapshotServiceTests` 覆盖 GRDB online backup 生成真实 SQLite snapshot、catalog/count/manifest 从 snapshot 自身读取、snapshot 不包含后续 live store 写入、snapshot hash 损坏标记 `invalid`、asset blob 缺失标记 `invalid`、catalog count 与 snapshot 漂移时标记 `invalid`、第 4 个恢复点淘汰最旧 snapshot 目录，以及 catalog 写入失败时清理 snapshot 目录。`./scripts/lint.sh` 退出码为 0，但仓库仍有既有 warning；本阶段新增 snapshot service / tests 仍有非阻断 function body length warning，暂不为消 warning 拆散流程。当前仍未实现 canonical 设置页恢复点 UI、迁移前安全点闸门、restore staging、canonical replace restore 和启动期 orphan snapshot 目录 reconciliation。

2026-07-10 本轮 canonical restore executor / restoreStaging pin / orphan recovery point 目录 reconciliation 的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalRestoreExecutorTests
```

结果：通过。`CanonicalRestoreExecutorTests` 覆盖 armed pending restore 替换 canonical store、保留当前本机 `libraryID` / `deviceID` 并写入新 `syncEpoch`、成功恢复后移除旧 `-wal` / `-shm`、unarmed pending 不替换当前 store 且释放 `restoreStaging` pin、损坏 armed pending 失败且不替换当前 store、缺失或损坏 pending context 时释放 `restoreStaging` pin、复制新库失败后 rollback 保留当前 store、已 stage 的恢复点即使被 retention 淘汰仍可从 pending payload 恢复，以及按 catalog 清理 orphan recovery point 目录和 `staging` 残留。当前仍未实现 canonical 设置页恢复点 UI、迁移前安全点闸门、生产启动接入和持久 `restore_job` 表。

2026-07-11 本轮 canonical boot restore gate 的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalBootRestoreGateTests
./scripts/test.sh --only MoodmentsTests/CanonicalRestoreExecutorTests
```

结果：通过。`CanonicalBootRestoreGateTests` 覆盖无 pending 时不创建 canonical root / DB、armed pending 在调用方打开 runtime 前完成替换、unarmed pending 被清理且不替换当前 store、损坏 armed payload 返回 failure 且保留当前 store、rollback 失败作为 `CanonicalRestoreCriticalError.rollbackFailed` 继续抛出。`CanonicalRestoreExecutorTests` 扩展覆盖底层 replace rollback 失败语义，避免启动期继续打开半替换 store。当前仍未把 canonical gate 接入普通 SwiftUI 生产启动、设置页 canonical 恢复点 UI、迁移前安全点闸门或持久 `restore_job` 表。

2026-07-11 本轮 canonical migration safety gate / 备份恢复 UI 服务边界的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/BackupRestoreServiceTests
./scripts/test.sh --only MoodmentsTests/CanonicalMigrationSafetyGateTests
./scripts/test.sh --only MoodmentsUITests/BackupRestoreUITests/testBackupListShowsSystemMaintainedRecoveryPointAndPreview
./scripts/test.sh --only MoodmentsUITests/BackupRestoreUITests/testPreparedRestoreRunsOnNextLaunchAndShowsSuccess
./scripts/lint.sh
git diff --check
```

结果：通过。`CanonicalMigrationSafetyGateTests` 覆盖 destructive migration / cutover 前创建 `.schemaMigration` 恢复点、创建失败不继续校验、校验失败中止、校验到不同或不可用恢复点时中止，以及恢复点保留策略仍生效。`BackupRestoreServiceTests` 覆盖 SwiftData 过渡恢复点和 canonical 恢复点映射到同一 UI value model；两条 `BackupRestoreUITests` 覆盖设置页通过本地适配器展示列表/预览，并完成准备恢复 -> 重启恢复成功提示。`BackupRestoreServicing` 只覆盖设置页列表、当前摘要和 prepare restore；启动期消费 pending restore 仍由当前生产 SwiftData 路径负责，canonical adapter 不能在 boot gate 接入前直接作为 production drop-in。当前仍未把 canonical runtime 接入普通生产启动，也未切换用户读写路径。

2026-07-11 本轮 Markdown 导出 M1 的定向验证：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/MarkdownExportServiceTests
./scripts/test.sh --only MoodmentsTests/MarkdownExportRendererTests
./scripts/test.sh --only MoodmentsTests/PDFExportServiceTests
./scripts/test.sh --only MoodmentsTests/PDFExportRendererTests
./scripts/test.sh --only MoodmentsUITests/MarkdownExportUITests
```

结果：通过。`MarkdownExportServiceTests` 覆盖从 SwiftData 活跃 Moment 快照生成 Markdown、写入相对 `assets/` 附件、保留照片字节、排除软删除记录，以及写入失败后清理未完成导出包；`MarkdownExportRendererTests` 覆盖标题/标签 Markdown 转义、正文换行归一和图片扩展名识别；`PDFExportServiceTests` 覆盖生成可读 PDF、稳定 `.pdf` 文件名、照片计数和坏图片失败；`PDFExportRendererTests` 覆盖长文分页、图片嵌入路径和坏图片快速失败；`MarkdownExportUITests` 覆盖设置页“导出”入口、详情页说明、生成 Markdown / PDF、成功态和系统分享入口。Markdown 分享入口指向整个导出目录，避免只分享 `.md` 时丢失相对 `assets/`；PDF 分享入口指向单个 `.pdf` 文件。当前 M1 只实现全部活跃时刻导出；筛选/日期范围、取消/重试和持久 `export_job` 仍在计划层。

2026-07-11 本轮 M2 main UI runtime cutover 的定向验证：

```bash
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/CanonicalLibraryServiceTests
./scripts/test.sh --only MoodmentsTests/EditorSaveValidationTests
./scripts/test.sh --only MoodmentsTests/ThumbnailCacheInvalidationTests
./scripts/test.sh --only MoodmentsTests/HeatmapMoodColorTests
./scripts/test.sh --only MoodmentsTests/LocalLibraryMutationServiceTests
```

结果：通过。`CanonicalLibraryServiceTests` 覆盖 canonical facade 的 prepare/changeToken、时间轴/预览/编辑值类型投影，以及 canonical backend 写入后刷新 `changeToken`；`EditorSaveValidationTests` 覆盖编辑模型在 canonical payload 下的保存校验、脏状态和编辑加载 baseline；`ThumbnailCacheInvalidationTests` 覆盖 canonical 原图读取和编辑保存后原 image ID 缩略图失效；`HeatmapMoodColorTests` 覆盖 canonical 聚合下的年度候选、每日心情和筛选聚合；`LocalLibraryMutationServiceTests` 确认 SwiftData transition backend 仍可通过既有测试，并覆盖 canonical backend 不再创建 SwiftData 稳定恢复点；`CanonicalRuntimeImportTests` 覆盖 SwiftData restore 成功后可在重新导入前清空旧 canonical storage；定向 UI 测试覆盖 UI seed 先写 SwiftData 再被 canonical baseline 导入。当前 M2 不包含 canonical 恢复点设置页切源和 Markdown / PDF canonical snapshot 切源，它们仍在计划层 M3/M4。
