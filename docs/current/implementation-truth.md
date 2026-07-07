# SwiftUI 当前实现真相

本文记录 SwiftUI 版 Moodments 当前已经实现的界面结构、运行路径和相对设计契约的偏离。这里的事实源是 `Sources/Moodments/` 与 `Tests/`，原 Flutter 项目只作为产品语义理解来源，不作为 SwiftUI 当前实现事实。

## 整体模型

当前 App 是单根首页结构：

```text
RootView
  -> TimelineHomeView
      -> TimelineListView
      -> top bar / context markers / FAB
  -> rootSheet: preview / editor / settings / paywall
  -> fullScreenCover: image viewer
  -> overlay: YearHeatmapView
```

`TimelineModel` 在 `RootView` 创建并注入首页与热力图，承载 `activeFilter` 和 `heatmapFocusDate`。这让“看哪些记录”和“定位到哪里”在代码层保持双状态源。

## 首页与时间轴

`TimelineHomeView` 负责首页壳层：主画布背景、顶部三入口、上下文标记、底部 FAB。`TimelineListView` 负责数据列表、标题折叠、筛选谓词、定位滚动和删除动作。

当前时间轴使用 SwiftUI `List`，不是自定义拖拽列表。每条 `TimelineRowView` 由三部分组成：

```text
dateColumn
  -> MoodNodeView
  -> BubbleCardView
```

`TimelineRowView` 用行背景画贯穿竖线，`MoodNodeView` 使用当前 Moment 的心情色，`BubbleCardView` 画圆角气泡和左侧尾巴。当前代码结构已经把日期列、节点列和气泡列放在同一行，并提供尾巴指向时间线的实现路径；真机视觉上的尖角对齐和比例关系不在本文证明范围内。

真实记录点击后写 `router.rootSheet = .preview(moment.id)`，左滑删除使用 `.swipeActions` 软删除到垃圾箱。引导记录不可点击、不可删除。

## 热力图与定位

`YearHeatmapView` 由 `RootView` 顶部 overlay 呈现。它不是 sheet，也不是 full screen cover；背景时间轴不下沉。

热力图当前行为：

- 年度聚合会读取当前 `activeFilter`，用于展示当前筛选口径下的年度分布。
- 点日期只写 `timelineModel.heatmapFocusDate`。
- `TimelineListView` 监听 `heatmapFocusDate` 后，在当前可见 `entries` 中计算滚动目标。
- 换年会清空 `heatmapFocusDate`。
- 再点同一天会取消定位高亮，不主动改回滚动位置。

这条路径保持“定位不等于筛选”：热力图选择不会改写 `activeFilter`，筛选变化也不会被当作时间锚点。

## 筛选与上下文标记

筛选入口只在标题折叠后出现。当前实现是 `TimelineHomeView` 局部 `isFilterPresented` 驱动的 `FilterPanelView` sheet，属于首页就地筛选层，不进入 `AppRouter.rootSheet`，也不进入任务卡片栈：

```text
collapsedTitleButton
  -> .sheet(isPresented:)
      -> FilterPanelView(activeFilter:)
          -> optional TagCreateSheetView
```

`FilterPanelView` 使用 `NavigationStack + List`。标签支持多选 AND，心情单选，点选即时写入 `activeFilter`；“完成”只负责收起 sheet，选择条件不会自动关闭 sheet。标签区末尾有“新增标签”入口，打开 `TagCreateSheetView` 第二层 sheet；创建成功后把新标签 id 并入当前筛选条件。

当前筛选 sheet 内没有显式“全部心情”行，也没有显式“清除全部”按钮。用户可以点已选心情取消心情条件、点已选标签取消单个标签条件，或通过首页上下文标记移除条件。

`TimelineContextMarkerBar` 同时显示筛选标记和时间定位标记。移除筛选标记改变 `activeFilter`，移除时间标记清空 `heatmapFocusDate`。

## 编辑页局部选择

`MomentEditorView` 是任务卡片栈第一层。情绪、标签、日期和时间选择当前由 SwiftUI 代码实现为局部选择：

- 情绪行打开 `MoodPickerView`。
- 标签行打开 `TagPickerView`。
- 顶栏日期 chip 打开 `DatePickerSheetView`。
- 顶栏时间 chip 打开 `TimePickerSheetView`。
- 这些选择器都由局部 `.popover` 呈现，不进入 `AppRouter`。
- 日期使用系统 `.graphical` `DatePicker`。
- 时间使用系统 `.wheel` `DatePicker`。
- 选择后通过 `OccurredAtComposer` 合成 `occurredAt`，只改变日期或只改变时间。
- 没有额外确认按钮。

这条代码路径使用系统日期/时间控件，未为基础 picker 重做自定义控件。当前测试面覆盖日期 popover 的打开/收起；时间 popover 与 `OccurredAtComposer` 即时回写仍缺窄测试覆盖。

## 设置与外观

`SettingsSheetView` 是根级第一层 sheet，内部使用 `NavigationStack + insetGrouped List`。设置子页包括统计、标签、垃圾箱、语言、外观、关于，均在设置栈内 push；Pro 横幅使用设置内部局部 `.sheet(item:)` 打开 `ProPaywallView`。

当前设置页仍有左上角“关闭”按钮。由于它本身是系统 sheet，用户也可通过系统下滑关闭；这个按钮是当前实现事实，但与“sheet 轻量、减少额外 chrome”的审计目标存在偏移。

`AppearanceThemeView` 已有四组设置：

```text
模式
颜色
网格
图片
```

这些选项通过 `ThemeManager` 即时更新并持久化到 `AppearanceStore`。保存失败和偏好修正提示使用页内文本，不走全局 alert。

当前外观设置的落地边界：

- 模式、主色会影响已接入 `ThemeManager` 的背景、文字、气泡、chip、热力图空格、顶栏图标描边等。
- 心情色通过 `theme.moodColor(_:)` 解析，不读取主色。
- 危险色通过 `theme.danger` 解析，不读取主色。
- `backgroundTexture` 已有 UI、状态和持久化，但首页背景当前只使用 `theme.canvasBackground`，没有实际绘制网格/点阵。
- `imageDisplayMode` 已有 UI、状态和持久化，但时间轴图片当前固定走横向 `ThumbnailStripView`，没有在滚动/轮播之间切换。

## 与设计层的已知漂移

| 漂移 | 当前事实 | 当前影响 |
| --- | --- | --- |
| 热力图位置 | 代码当前是顶部 overlay 卡片。 | 与“导航栏下方稳定上下文区”的优化方向不同。 |
| 筛选 sheet 控件 | 设计期望 sheet 内有“全部心情”和“清除全部”；当前 sheet 内没有显式控件。 | 仍可通过点已选项或上下文标记移除条件，但筛选面板自身的重置语义不够直接。 |
| 设置关闭按钮 | 代码当前显式提供“关闭”。 | 与轻量 sheet 依赖系统下滑关闭的方向存在偏移。 |
| 外观页预览 | 代码当前是 `List` 行 + 勾选。 | 主题效果主要通过文字行表达，不是通过真实预览表达。 |
| 背景纹理 | 已有设置轴，未驱动首页纹理渲染。 | UI 选项和实际效果不闭环。 |
| 图片展示方式 | 已有设置轴，未驱动气泡图片展示切换。 | 设置项和内容行为不闭环。 |
| 亮色心情色 | 亮色下除 `.normal` 外仍沿用暗色推导值。 | 不影响主色独立性；亮色效果缺少独立取色事实。 |

## Flutter 版只作为语义输入

原 Flutter 项目只作为产品语义输入；SwiftUI current 事实以本仓库 `Sources/Moodments/` 与 `Tests/` 为准。Flutter 中的 `showCupertinoSheet`、`GlobalKey + ScrollController`、自定义气泡 shape、Flutter picker 组合、开发者皮肤轴等都不是 SwiftUI 必须照搬的实现细节。
