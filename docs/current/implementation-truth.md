# SwiftUI 当前实现真相

本文记录 SwiftUI 版 Moodments 当前已经实现的界面结构、运行路径和相对设计契约的偏离。这里的事实源是 `Sources/Moodments/` 与 `Tests/`，原 Flutter 项目只作为产品语义理解来源，不作为 SwiftUI 当前实现事实。

## 整体模型

当前 App 是单根首页结构：

```text
RootView
  -> TimelineHomeView
      -> TimelineHomeChromeView
      -> HomeContextPanel(YearHeatmapView)
      -> TimelineViewportView
      -> TimelineContextMarkerBar
      -> TimelineFilterSheetPresenter(FilterPanelView)
      -> FAB
  -> rootSheet: preview / editor / settings / paywall
  -> fullScreenCover: image viewer
```

`TimelineModel` 在 `RootView` 创建并注入首页与热力图，承载 `activeFilter`、`heatmapFocusDate` 和 `heatmapAnchorGranularity`。这让“看哪些记录”和“定位到哪里”在代码层保持双状态源，并能表达日/月两种时间 anchor 粒度。

## 首页与时间轴

`TimelineHomeView` 负责首页场景壳层：主画布背景、列表、顶部上下文槽位、底部 FAB 和创建额度闸门。顶部入口已拆到 `TimelineHomeChromeView`；热力图插槽由 `HomeContextPanel` 包住；筛选 half-sheet 的 `.sheet` 修饰符集中在 `TimelineFilterSheetPresenter`，仍由首页局部 `isFilterPresented` 驱动，不进入 `AppRouter`。

`TimelineViewportView` 负责时间轴 viewport、标题折叠、筛选谓词、定位滚动和删除副作用；它不持有热力图展开、筛选 sheet 展开或设置 sheet 呈现状态。

当前时间轴使用 SwiftUI `ScrollViewReader + List`：`List` 只作为成熟滚动和行级 swipe action 宿主，不作为时间轴轨道坐标来源。每条 `TimelineRowView` 由三部分组成：

```text
TimelineDateColumn
  -> TimelineMoodAnchorColumn(MoodNodeView)
  -> BubbleCardView
```

`TimelineGeometry` 是首页时间轴坐标系统的单一来源，把时间轴视为主页滚动场景中的局部坐标轴：`railCenterXInRow` 定义轨道相对阅读单元左边缘的横坐标，`initialRailCenterX` / `initialRailTopY` 定义轨道默认位置，`firstNodeCenterYOffsetFromRailTop` 定义默认态轨道顶点到第一条 Moment 心情节点中心的向下 y 偏移，`railLeadInHeight` 定义轨道顶点和第一条阅读单元之间的呼吸空间，`railBottomOvershoot` 定义最后一条 Moment 之后继续延伸的轨道长度，`nodeCenterY` / `bubbleTailCenterY` 定义心情节点和气泡尾巴之间的纵向锚定关系，`bubbleTailSize` / `bubbleTailHorizontalOffset` 定义气泡尾巴自身几何。后续如果要移动时间轴位置、调整日期列、节点列或气泡尾巴关系，优先改这个几何基准，而不是在多个对象里改散落 padding。

`TimelineViewportView` 用 `ZStack` 组合独立的 `TimelineRailLayer` 和 `List` 滚动内容层。轨道不属于任何一条 `TimelineRowView`，也不进入可滑动阅读单元；它是首页时间轴场景的结构层。轨道 x 坐标直接来自 `TimelineGeometry.initialRailCenterX`，top 直接来自 `TimelineGeometry.initialRailTopY`，不依赖当前可见 Moment，也不通过某个心情节点或行内 probe 反推时间轴位置。滚动 offset 在 iOS 18+ 使用 SwiftUI `onScrollGeometryChange`，iOS 17 使用挂在 `List` 自身的零尺寸 `TimelineScrollOffsetReader` 读取承载 `UIScrollView`；这条读取链路只驱动标题折叠和轨道纵向相位，不参与轨道定位。轨道 y 坐标采用混合滚动行为：下拉时顶点保持在标题区下方的初始位置，上滑时轨道随时间轴场景向上移动，底部通过 overshoot 延伸到屏幕外。顶部标题栏展开态保持透明，折叠态使用 SwiftUI `Material` 形成毛玻璃过渡，让内容向上滚动时仍保持时间轴稳定穿过主场景的感知。

`TimelineRowView` 只承载日期列、心情节点和气泡组成的阅读单元。左滑删除由 SwiftUI `List` 行的 `.swipeActions(edge: .trailing, allowsFullSwipe: true)` 提供，所以轻扫露出删除按钮、继续左滑按钮拉长并触发删除都交给系统成熟组件；连续时间轴轨道不参与横向位移。节点中心、气泡尾巴中心和尾巴尺寸/偏移由 `TimelineGeometry` 约束，再传入 `BubbleCardView`；当前代码结构已经把轨道、日期列、节点列和气泡列放到同一坐标系统中，并提供尾巴指向时间线的实现路径；真机视觉上的尖角对齐、比例关系和滑动删除过程中的最终观感仍需截图/录屏验收。

真实记录点击气泡后写 `router.rootSheet = .preview(moment.id)`，VoiceOver 默认动作同样打开预览阅读卡片。左滑阅读单元使用系统 `.swipeActions` 软删除到垃圾箱；轻扫会露出“删除”按钮，继续滑动可触发系统 full swipe 删除；VoiceOver 删除替代路径挂在行级可访问元素上。引导记录不可点击、不可删除。

根级 sheet 或筛选 sheet 展开时，`TimelineHomeView` 保留主页时间轴层级，不卸载 `TimelineViewportView`，以维持主场景返回态和滚动连续性；同时通过 `suppressAccessibility` 把后台时间轴行从可访问树中压低，避免临时任务上下文中误操作背景内容。垃圾箱相关 UI 测试只命中 `trashRow-*`，不把后台同名 Moment 行当作垃圾箱行。

## 热力图与定位

`YearHeatmapView` 由 `TimelineHomeView` 的首页局部 `isHeatmapPresented` 状态驱动，插入顶部 `safeAreaInset` 中的 `topBar` 下方。它不是 sheet、不是 full screen cover，也不进 `AppRouter`；展开后作为主页顶部上下文区参与布局，继承 `theme.canvasBackground`，并用底部分隔线和主页内容区分。

热力图当前行为：

- 年度聚合会读取当前 `activeFilter`，用于展示当前筛选口径下的年度分布。
- 点日期写入日粒度 anchor；点有记录的月份标签写入月粒度 anchor。两者都只更新 `timelineModel.heatmapFocusDate` 和 `timelineModel.heatmapAnchorGranularity`；当前热力图口径下没有记录的月份只显示文本，不提供月份定位按钮。
- `HeatmapGridView` 在月粒度选中时用当前主色低透明蒙层覆盖对应月份列区，蒙层位于日期格上方且不拦截点击；日粒度选中时仍用日期格描边。
- `TimelineViewportView` 监听包含 anchor 日期、粒度和目标行的派生滚动请求后，在当前可见 `entries` 中计算滚动目标；日 anchor 只命中同一天真实记录，月 anchor 只命中同一月真实记录，不会退到更早日期或更早月份。
- 换年会清空 `heatmapFocusDate`。
- 再点同一天或同一月会取消定位高亮，不主动改回滚动位置。

这条路径保持“定位不等于筛选”：热力图选择不会改写 `activeFilter`，筛选变化也不会被当作时间锚点。筛选变化后，如果当前可见集内没有该日或该月真实记录，定位标记仍可保留，但滚动目标为 `nil`，不会偷偷放宽筛选；空态引导卡片不参与日/月 anchor 目标计算。

## 筛选与上下文标记

筛选入口只在标题折叠后出现。当前实现是 `TimelineHomeView` 局部 `isFilterPresented` 驱动的 `FilterPanelView` sheet，属于首页就地筛选层，不进入 `AppRouter.rootSheet`，也不进入任务卡片栈：

```text
TimelineHomeView.timelineFilterSheet
  -> .sheet(isPresented:)
      -> FilterPanelView(activeFilter:)
```

`FilterPanelView` 使用 `NavigationStack + ScrollView + LazyVGrid`。标签支持多选 AND，心情单选，显式提供“全部心情”；点选即时写入 `activeFilter`；“完成”只负责收起 sheet，选择条件不会自动关闭 sheet；“清除全部”会一次性移除心情和标签筛选。筛选 sheet 只选择已有标签，不提供新增、重命名、删除入口，也不会打开 `TagCreateSheetView` 第二层 sheet。

`TimelineContextMarkerBar` 同时显示筛选标记和时间定位标记。移除筛选标记改变 `activeFilter`，移除时间标记清空 `heatmapFocusDate` 与 `heatmapAnchorGranularity`。日 anchor 显示为 `M月d日`，月 anchor 显示为 `M月`。

## 编辑页局部选择

`MomentEditorView` 是任务卡片栈第一层。情绪、标签、日期和时间选择当前由 SwiftUI 代码实现为局部选择：

- 情绪行打开 `MoodPickerView`。
- 标签行打开 `TagPickerView`，只选择已有标签，不提供新增入口。
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

`TagManageView` 是当前标签新增、重命名、删除的唯一管理入口。右上“+”在打开 `TagCreateSheetView` 前经 `QuotaService` 做标签额度闸门，超额时打开 `ProPaywallView`；`TagCreateSheetView` 在真正创建新标签前再次复核标签额度，避免表单打开后数量变化造成越额写入。列表行点击进入重命名，左滑使用统一的系统 `.swipeActions(allowsFullSwipe: true)` 展示删除按钮并支持 full swipe。删除成功后调用 `TimelineModel.discardFilterTag` 清理当前筛选中可能残留的标签 id。

当前设置页仍有左上角“关闭”按钮。由于它本身是系统 sheet，用户也可通过系统下滑关闭；这个按钮是当前实现事实。

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
| 设置关闭按钮 | 代码当前显式提供“关闭”。 | 除系统下滑关闭外，还额外显示一个关闭路径，界面 chrome 更多。 |
| 外观页预览 | 代码当前是 `List` 行 + 勾选。 | 主题效果主要通过文字行表达，缺少真实预览。 |
| 背景纹理 | 已有设置轴，未驱动首页纹理渲染。 | UI 选项和实际效果不闭环。 |
| 图片展示方式 | 已有设置轴，未驱动气泡图片展示切换。 | 设置项和内容行为不闭环。 |
| 亮色心情色 | 亮色下除 `.normal` 外仍沿用暗色推导值。 | 不影响主色独立性；亮色效果缺少独立取色事实。 |

## P0 验证事实

2026-07-07 已运行：

```sh
./scripts/test.sh --unit
./scripts/test.sh --ui
```

结果：`./scripts/test.sh --unit` 通过。`MoodmentsTests` 执行 110 个测试，4 个 StoreKit 环境相关测试按既有策略跳过，0 失败。`./scripts/test.sh --ui` 通过。`MoodmentsUITests` 执行 34 个 UI 测试，0 失败。UI 覆盖包括创建、预览、左滑软删除、垃圾箱恢复、彻底删除确认、热力图日/月定位、筛选标记、标题折叠筛选入口、空态、主题/外观设置、语言、隐私锁、标签管理和额度闸门。

仍未由自动化证明的 P0 / 架构稳定视觉项：

- 真机截图中节点中心、气泡尾巴和时间轴竖线是否形成足够明确的绑定。
- 左滑删除过程中系统 `.swipeActions` 的视觉位移是否满足“阅读单元整体从轨道移走、轨道背景保持连续”的边界；若需微调，只能限制在行操作层，不回退到行内轨道或 probe。
- 热力图顶部上下文区在不同屏宽和明暗主题下是否足够像主页上下文，而不是漂浮卡片。

## Flutter 版只作为语义输入

原 Flutter 项目只作为产品语义输入；SwiftUI current 事实以本仓库 `Sources/Moodments/` 与 `Tests/` 为准。Flutter 中的 `showCupertinoSheet`、`GlobalKey + ScrollController`、自定义气泡 shape、Flutter picker 组合、开发者皮肤轴等都不是 SwiftUI 必须照搬的实现细节。
