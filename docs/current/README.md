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
| 时间轴阅读单元 | 已落地。每行由日期列、心情节点、气泡内容组成，真实记录支持点开预览和左滑软删除。 | `TimelineListView.swift`、`TimelineRowView.swift`、`MoodNodeView.swift`、`BubbleCardView.swift` |
| 时间轴连续性 | 代码路径已改为行背景贯穿绘制竖线；真机视觉对齐尚未在 current 层形成验收证据。 | `TimelineRowView.swift` |
| 热力图定位 | 已落地。热力图是顶部 overlay；点日期只写 `heatmapFocusDate` 并滚动定位，不改筛选条件。当前没有月份点选入口。 | `RootView.swift`、`YearHeatmapView.swift`、`TimelineListView.swift` |
| 筛选 | 已落地。当前是首页局部半屏/大屏 `FilterPanelView` sheet，不进 `AppRouter.rootSheet`，点选即时生效且选择后不自动关闭。 | `TimelineHomeView.swift`、`FilterPanelView.swift` |
| 上下文标记 | 已落地。筛选标记和时间定位标记可并存、可分别移除。 | `TimelineContextMarkerBar.swift`、`TimelineModel.swift` |
| 编辑页日期/时间选择 | 代码已落地。日期和时间由局部 `.popover` 打开系统 `DatePicker`，即时回写 `occurredAt`；时间 popover 与即时回写仍缺窄测试覆盖。 | `MomentEditorView.swift`、`DateTimePopovers.swift` |
| 设置流 | 已落地。设置页是第一层 sheet，子页在设置内 `NavigationStack` push；Pro 可作为设置内第二层 sheet。 | `SettingsSheetView.swift` |
| 外观设置 | 部分落地。模式、主色、背景纹理、图片展示已有 UI、内存态和持久化；`backgroundTexture` 尚未接入首页背景绘制，`imageDisplayMode` 尚未接入气泡图片展示路径。 | `AppearanceThemeView.swift`、`ThemeManager.swift`、`TimelineHomeView.swift`、`BubbleCardView.swift` |
| 主题语义 | 已落地。主色、心情色、危险色由不同语义入口暴露，心情色和危险色不跟随主色。 | `ThemeManager.swift`、`Colors.swift` |

## 当前验证基线

本次文档基线来自静态代码审计、现有测试文件梳理和原 Flutter 项目语义对照；没有改动 Swift 代码。

与本 current 相关的已有测试面包括：

- `Tests/MoodmentsTests/LocateVsFilterTests.swift`
- `Tests/MoodmentsTests/HeatmapMoodColorTests.swift`
- `Tests/MoodmentsTests/MoodColorPaletteTests.swift`
- `Tests/MoodmentsTests/AppearanceStoreTests.swift`
- `Tests/MoodmentsTests/EditorSaveValidationTests.swift`
- `Tests/MoodmentsUITests/CreateMomentFlowUITests.swift`
- `Tests/MoodmentsUITests/TitleCollapseFilterUITests.swift`
- `Tests/MoodmentsUITests/LocateFilterUITests.swift`
- `Tests/MoodmentsUITests/EditorSheetPresentationUITests.swift`
- `Tests/MoodmentsUITests/ThemeSwitchUITests.swift`
- `Tests/MoodmentsUITests/AppearanceSaveFailureUITests.swift`

文档层验证命令：

```sh
rg -n "docs/current|docs/plans|implementation-truth|implementation-plan" CLAUDE.md docs
```
