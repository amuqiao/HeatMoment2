# 当前实现真相

本文是 SwiftUI 版 Moodments 的 current 入口，只记录当前代码已经落地的事实、已知偏离和验证基线。设计目标与产品契约仍以 [`../product-mental-model.md`](../product-mental-model.md) 和 [`../design/`](../design/README.md) 为准；尚未实现的优化进入 [`../plans/implementation-plan.md`](../plans/implementation-plan.md)。

## 文档边界

`current` 回答“现在实际怎么实现”。它不承诺未来优化，不替代设计层，也不把 Flutter 版实现细节当作 SwiftUI 事实。

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
| 时间轴连续性 | 结构归属已调整。连续轨道由 `TimelineRailSceneLayer` 承载在 `TimelineViewportView` 场景层，不属于任何 `List` row；阅读单元位于行前景。轨道 x、节点中心、日期列和气泡尾巴关系由 `TimelineGeometry` 集中定义；轨道可见性由 `TimelineRailVisibility` 收口，只有存在阅读单元时才渲染，筛选空态不留下孤立轨道。滚动宿主使用 SwiftUI `List`，删除使用系统 `.swipeActions(allowsFullSwipe: true)`，支持轻扫露出按钮和继续滑动触发删除；真实 Moment 的 VoiceOver 默认动作打开预览，删除作为命名动作保留。定向单元测试已锁住节点中心与轨道 x 的坐标合同。 | `TimelineGeometry.swift`、`TimelineRailVisibility.swift`、`TimelineRailSceneLayer.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`BubbleCardView.swift` |
| 热力图定位 | 已落地。热力图由首页局部状态在导航栏下方原位展开，作为顶部上下文区参与主页布局；点日/点有记录的月份只写时间 anchor，不改筛选条件。选中月份用主色低透明蒙层标记。 | `TimelineHomeView.swift`、`YearHeatmapView.swift`、`HeatmapGridView.swift`、`TimelineViewportView.swift` |
| 筛选 | 已落地。当前是首页局部半屏/大屏 `FilterPanelView` sheet，不进 `AppRouter.rootSheet`，标签/心情以紧凑网格选择，提供“全部心情”和“清除全部”，点选即时生效且选择后不自动关闭；筛选 sheet 只选择已有标签，不提供标签新增入口。 | `TimelineHomeView.swift`、`FilterPanelView.swift` |
| 上下文标记 | 已落地。筛选标记和时间定位标记可并存、可分别移除。 | `TimelineContextMarkerBar.swift`、`TimelineModel.swift` |
| 编辑页日期/时间选择 | 代码已落地。日期和时间由局部 `.popover` 打开系统 `DatePicker`，即时回写 `occurredAt`；时间 popover 与即时回写仍缺窄测试覆盖。 | `MomentEditorView.swift`、`DateTimePopovers.swift` |
| 设置流 | 已落地。设置页是第一层 sheet，子页在设置内 `NavigationStack` push；Pro 可作为设置内第二层 sheet。标签新增、重命名、删除归属 `TagManageView`，新增入口和保存创建前都做标签额度闸门，删除使用系统 `.swipeActions(allowsFullSwipe: true)`。 | `SettingsSheetView.swift`、`TagManageView.swift` |
| 外观设置 | 部分落地。模式、主色、图片展示已有 UI、内存态、持久化和实际消费路径；`imageDisplayMode` 已驱动首页气泡图片区在横向缩略图布局和轮播布局之间切换。`backgroundTexture` 尚未接入首页背景绘制。 | `AppearanceThemeView.swift`、`ThemeManager.swift`、`TimelineHomeView.swift`、`BubbleCardView.swift`、`ThumbnailStripView.swift` |
| 主题语义 | 已落地。主色、心情色、危险色由不同语义入口暴露，心情色和危险色不跟随主色。 | `ThemeManager.swift`、`Colors.swift` |

## 当前验证基线

本次 current 基线来自 P0 实现后的代码审计、定向单元测试、定向 UI 测试、构建和 lint 验证。

脚本与测试入口已收口到 [`../../scripts/README.md`](../../scripts/README.md) 描述的三层模型：`dev.sh` 是日常门面，`test.sh` 是 XCTest/XCUITest 统一入口，`verify.sh` 是本地与 CI 共用的一条龙验证入口。测试数据隔离和 UI launch arguments 的 current 契约见 [`testing-architecture.md`](testing-architecture.md)。

与本 current 相关的已有测试面包括：

- `Tests/MoodmentsTests/LocateVsFilterTests.swift`
- `Tests/MoodmentsTests/HeatmapMoodColorTests.swift`
- `Tests/MoodmentsTests/MoodColorPaletteTests.swift`
- `Tests/MoodmentsTests/AppearanceStoreTests.swift`
- `Tests/MoodmentsTests/MomentCardLayoutTests.swift`
- `Tests/MoodmentsTests/EditorSaveValidationTests.swift`
- `Tests/MoodmentsUITests/CreateMomentFlowUITests.swift`
- `Tests/MoodmentsUITests/TitleCollapseFilterUITests.swift`
- `Tests/MoodmentsUITests/LocateFilterUITests.swift`
- `Tests/MoodmentsUITests/DeleteRestorePurgeUITests.swift`
- `Tests/MoodmentsUITests/EditorSheetPresentationUITests.swift`
- `Tests/MoodmentsUITests/ThemeSwitchUITests.swift`
- `Tests/MoodmentsUITests/AppearanceSaveFailureUITests.swift`

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
