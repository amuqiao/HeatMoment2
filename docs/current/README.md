# 当前实现真相

本文是 SwiftUI 版 Moodments 的 current 入口，只记录当前代码已经落地的事实、已知偏离和验证基线。设计目标与产品契约仍以 [`../product-mental-model.md`](../product-mental-model.md) 和 [`../design/`](../design/README.md) 为准；尚未实现的优化进入 [`../plans/implementation-plan.md`](../plans/implementation-plan.md)。

## 文档边界

`current` 回答“现在实际怎么实现”。它不承诺未来优化，不替代设计层，也不把 Flutter 版实现细节当作 SwiftUI 事实。

| 文件 | 职责 |
| --- | --- |
| [`implementation-truth.md`](implementation-truth.md) | SwiftUI 版当前 as-built 架构、界面流、主题/时间轴/设置等落地事实与偏离 |
| 本文 | current 层阅读入口、能力矩阵和验证基线 |

## 能力矩阵

| 能力 | 当前状态 | 事实源 |
| --- | --- | --- |
| 单根首页 | 已落地。`TimelineHomeView` 是根体验，根级任务卡片由 `RootView` 的 `.sheet(item:)` 承载。 | `Sources/Moodments/App/RootView.swift`、`Sources/Moodments/Features/Timeline/TimelineHomeView.swift` |
| 首页场景壳 | 已落地。顶部 chrome、热力图上下文槽位、筛选 half-sheet presenter、时间轴列表和 FAB 已拆成独立组合点。 | `TimelineHomeView.swift`、`TimelineHomeChromeView.swift`、`TimelineHomePresentation.swift` |
| 时间轴阅读单元 | 已落地。每行由日期列、心情节点、气泡内容组成；三者是可分别调样式的对象，但左滑删除的视觉目标是这一整条阅读单元。位置、节点锚点和气泡尾巴几何由 `TimelineGeometry` 集中定义，方便后续移动时间轴、锚定节点和调整气泡尾巴。 | `TimelineGeometry.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`MoodNodeView.swift`、`BubbleCardView.swift` |
| 时间轴连续性 | 结构归属已调整。连续轨道由 `TimelineViewportView` 的独立 `TimelineRailLayer` 绘制，不属于任何 `TimelineRowView`，也不进入可滑动阅读单元。轨道 x/top 直接来自 `TimelineGeometry`；轨道 y 下拉时保持初始顶点，上滑时随时间轴场景向上移动，底部通过 overshoot 延伸到屏幕外。滚动宿主使用 SwiftUI `List`，删除使用系统 `.swipeActions(allowsFullSwipe: true)`，支持轻扫露出按钮和继续滑动触发删除；真实 Moment 的 VoiceOver 默认动作打开预览，删除作为命名动作保留。真机视觉对齐与滑动删除位移边界仍需截图/录屏验收。 | `TimelineGeometry.swift`、`TimelineRailLayer.swift`、`TimelineViewportView.swift`、`TimelineRowView.swift`、`BubbleCardView.swift` |
| 热力图定位 | 已落地。热力图由首页局部状态在导航栏下方原位展开，作为顶部上下文区参与主页布局；点日/点有记录的月份只写时间 anchor，不改筛选条件。选中月份用主色低透明蒙层标记。 | `TimelineHomeView.swift`、`YearHeatmapView.swift`、`HeatmapGridView.swift`、`TimelineViewportView.swift` |
| 筛选 | 已落地。当前是首页局部半屏/大屏 `FilterPanelView` sheet，不进 `AppRouter.rootSheet`，点选即时生效且选择后不自动关闭。 | `TimelineHomeView.swift`、`FilterPanelView.swift` |
| 上下文标记 | 已落地。筛选标记和时间定位标记可并存、可分别移除。 | `TimelineContextMarkerBar.swift`、`TimelineModel.swift` |
| 编辑页日期/时间选择 | 代码已落地。日期和时间由局部 `.popover` 打开系统 `DatePicker`，即时回写 `occurredAt`；时间 popover 与即时回写仍缺窄测试覆盖。 | `MomentEditorView.swift`、`DateTimePopovers.swift` |
| 设置流 | 已落地。设置页是第一层 sheet，子页在设置内 `NavigationStack` push；Pro 可作为设置内第二层 sheet。 | `SettingsSheetView.swift` |
| 外观设置 | 部分落地。模式、主色、背景纹理、图片展示已有 UI、内存态和持久化；`backgroundTexture` 尚未接入首页背景绘制，`imageDisplayMode` 尚未接入气泡图片展示路径。 | `AppearanceThemeView.swift`、`ThemeManager.swift`、`TimelineHomeView.swift`、`BubbleCardView.swift` |
| 主题语义 | 已落地。主色、心情色、危险色由不同语义入口暴露，心情色和危险色不跟随主色。 | `ThemeManager.swift`、`Colors.swift` |

## 当前验证基线

本次 current 基线来自 P0 实现后的代码审计和单元测试验证。

与本 current 相关的已有测试面包括：

- `Tests/MoodmentsTests/LocateVsFilterTests.swift`
- `Tests/MoodmentsTests/HeatmapMoodColorTests.swift`
- `Tests/MoodmentsTests/MoodColorPaletteTests.swift`
- `Tests/MoodmentsTests/AppearanceStoreTests.swift`
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

P0 代码验证命令：

```sh
./scripts/test.sh --unit
./scripts/test.sh --ui
```

结果：2026-07-07，`./scripts/test.sh --unit` 通过，108 个测试、4 个 StoreKit 环境相关 skip、0 失败。`./scripts/test.sh --ui` 通过，33 个 UI 测试、0 失败。UI 覆盖包括创建、预览、左滑软删除、垃圾箱恢复、彻底删除确认、热力图日/月定位、筛选标记、标题折叠筛选入口、空态、主题/外观设置、语言、隐私锁和额度闸门。真机截图层面的时间轴视觉对齐、左滑过程中轨道与阅读单元的像素级连续感仍需人工复核。
