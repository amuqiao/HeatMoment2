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
| 数据持久化 | 生产 UI 路径已落地但属于过渡形态。当前用户写入仍使用 SwiftData `Moment` / `Tag` / `MomentImage`，生产启动路径会尝试 SwiftData + CloudKit 私有库容器，不可用时回退本地容器；UI 用户写入入口经 `LocalLibraryMutationService` 编排后再调用 SwiftData repository，同步状态仅由 CloudKit 是否启用、网络可达性和最近本地写入时间启发式推导。GRDB canonical local core 已有 schema、repository、`CanonicalLibraryRuntime` 装配类型、content-addressed `FileAssetStore` 和 SwiftData baseline 导入器；导入器已把 SwiftData 原图字节写入 asset store，并用 SQLite `asset_record` 保存 hash/MIME/尺寸/字节数 metadata。当前 App 启动不打开 canonical 持久库，canonical 尚未接入生产 UI，也不是双写路径。目标数据生命周期见计划层，不把当前 SwiftData 模型定义为最终权威。 | `ModelContainer+Config.swift`、`MoodmentsApp.swift`、`Moment.swift`、`Tag.swift`、`MomentImage.swift`、`LocalLibraryMutationService.swift`、`SyncStatusService.swift`、`CanonicalStore.swift`、`CanonicalLibraryRuntime.swift`、`FileAssetStore.swift`、`SwiftDataCanonicalImporter.swift`、`CanonicalLibraryRepository.swift` |
| 本地自动恢复点 | 已落地最小 SwiftData 过渡版。非 CloudKit 本地容器下，App 自动维护最多 3 个恢复点；普通用户写入后经 `LocalLibraryMutationService` 按稳定变更节流创建恢复点；垃圾箱恢复/彻底删除、标签删除和恢复点 replace restore 前创建操作安全点。设置页提供“备份与恢复”列表和恢复预览；用户可恢复、不可删除恢复点；准备恢复后进入阻断页等待重启，冷启动完成后提示恢复结果。 | `LocalLibraryMutationService.swift`、`LocalBackupCoordinator.swift`、`RecoveryPointManager.swift`、`LocalBackupRestoreExecutor.swift`、`BackupRestoreView.swift`、`PendingLocalRestoreView.swift` |
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
- `Tests/MoodmentsTests/CanonicalRuntimeImportTests.swift`
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

结果：全部通过。`FileAssetStoreTests` 覆盖 content-addressed 原图写入、按 hash 读回、相同 bytes 去重，以及 expected hash mismatch 快速失败且不产生 blob；`CanonicalRuntimeImportTests` 扩展覆盖 SwiftData baseline 导入后 `asset_record.content_hash` 与真实 asset store 文件一致、两个相同原图只落一个 content-addressed blob。本轮仍未实现 asset pin、reachability audit、GC、canonical recovery catalog 或导出任务。
