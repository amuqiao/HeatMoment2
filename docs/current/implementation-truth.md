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

`TimelineSceneMetrics` 是首页时间轴视觉骨架入口，由 `TimelineHomeView` 按当前 viewport 宽度和 `ThemeManager.timelineSceneStyle` 计算一次，再传给 `TimelineViewportView`。它拆成 `TimelineSceneLayout` 和 `TimelineSceneStyle` 两层：layout 只表达日期列、轨道、节点外径、气泡尾巴、标题、顶部 chrome 和 FAB 直径/避让等坐标与呼吸节奏；style 只表达字体、节点内圆比例与透明度、气泡内部形状/内容节奏、图片区、tag chip、顶部图标和 FAB 图标/阴影等视觉参数，不反推时间轴锚点。`TimelineResponsiveScale` 以 390pt 宽 iPhone 为基准，对窄屏小幅收紧、宽屏小幅放大，并做半点取整，避免不同手机尺寸上视觉对象漂移或撑爆容器。

`TimelineGeometry` 是首页时间轴阅读单元坐标系统的单一来源：`listHorizontalInset` 定义整条阅读单元的行内缩进，`dateColumnWidth` / `interColumnSpacing` / `nodeColumnWidth` 定义日期列、节点列和气泡列的横向关系，`readingUnitOriginX` / `nodeCenterXInReadingUnit` / `nodeCenterXInViewport` / `railCenterXInViewport` 定义节点中心与视口轨道的 x 绑定，`bubbleLeadingXInReadingUnit` 定义气泡卡片相对阅读单元的起点，`firstNodeCenterYOffsetFromRailTop` 定义默认态轨道顶点到第一条 Moment 心情节点中心的向下 y 偏移，`railLeadInHeight` 定义轨道顶点和第一条阅读单元之间的呼吸空间，`nodeDiameter` 定义心情节点外径，`nodeCenterY` / `bubbleTailCenterY` 定义心情节点和气泡尾巴之间的纵向锚定关系，`railWidth` 定义轨道线宽，`bubbleTailSize` / `bubbleTailHorizontalOffset` 定义气泡尾巴自身几何。`TimelineViewportLayout` 定义首页首屏场景槽位：展开标题槽位底部、展开标题自身顶部 padding、标题到轨道顶点的呼吸间隔和轨道底部超出长度；`TimelineHomeLayout` 定义首页固定 chrome 与 FAB 的场景避让，包括顶部 chrome padding、FAB 直径、FAB 吸底距离和底部操作 clearance。`TimelineViewportMetrics` 消费 viewport layout、viewport 尺寸和滚动 offset，生成 `TimelineRailSceneBounds`。场景轨道的顶点和底端由 `TimelineRailSceneLayer` 消费 `TimelineViewportMetrics` 绘制，不再反向依赖 `List` 行的 `PreferenceKey` 上报；`List` 是惰性布局，不能作为整条轨道是否存在的真相源。后续如果要移动时间轴横向位置、调整日期列、节点列或气泡尾巴关系，优先改 `TimelineGeometry`；如果要调整轨道首屏 y、标题到轨道顶点间隔或底部超出，优先改 `TimelineViewportLayout`；如果要调整顶部 chrome 或 FAB 避让，优先改 `TimelineHomeLayout`；如果要调整字体、节点内圆、气泡内部样式、顶部图标或 FAB 图标/阴影，优先改 `TimelineSceneStyle` 或 `ThemeManager.timelineSceneStyle`；如果要调整上滑/下拉相位，优先改 `TimelineViewportMetrics`。

`TimelineViewportView` 使用 `ScrollViewReader + List` 承载成熟滚动、定位和行级 swipe action。连续轨道由 `TimelineRailSceneLayer` 作为 viewport 场景层绘制，不属于任何 `List` row、阅读单元或气泡；日期列、心情节点和气泡是行前景阅读单元。`TimelineRailVisibility` 决定是否渲染场景轨道：只有存在可见阅读单元时才画轨道；筛选后 0 条命中时只显示空态文案，不渲染轨道或 lead-in / bottom overshoot，避免出现没有日期、节点、气泡归属的孤立竖线。轨道场景层不参与 `List` 行级 `.swipeActions`，因此左滑删除时系统移动日期、节点和气泡这个阅读单元，轨道不会被 row swipe 容器移动、裁剪或切断。滚动监听在 iOS 18+ 使用 SwiftUI `onScrollGeometryChange`，iOS 17 使用挂在 `List` 自身的零尺寸 `TimelineScrollOffsetReader` 读取承载 `UIScrollView`；这条读取链路输出 viewport 滚动相位，用于标题折叠和轨道 y 相位，不反推轨道 x 坐标或节点位置。

`TimelineRowView` 只承载日期列、心情节点和气泡组成的阅读单元。左滑删除由 SwiftUI `List` 行的 `.swipeActions(edge: .trailing, allowsFullSwipe: true)` 提供，所以轻扫露出删除按钮、继续左滑按钮拉长并触发删除都交给系统成熟组件；连续时间轴轨道不参与横向位移。节点中心、气泡尾巴中心和尾巴尺寸/偏移由 `TimelineGeometry` 约束，再传入 `BubbleCardView`；当前代码结构已经把轨道、日期列、节点列和气泡列放到同一坐标系统中，并提供尾巴指向时间线的实现路径。

`BubbleCardView` 是首页 Moment 气泡的展示合同：标题、正文和图片按 `MomentCardContentKind` 覆盖标题-only、正文-only、标题+正文、文字+图片、纯图片等状态；气泡宽度跟随时间轴内容列，不由标题长度、图片数量或原图比例反向撑开。气泡圆角、内边距、内容间距、尾巴、图片区和 tag chip 由 `TimelineBubbleStyle` 注入，后续皮肤替换气泡形状或图片区节奏不需要改行级坐标。图片区尺寸由 `MomentCardLayout` 转发 `TimelineImageGalleryStyle.standard` 固定：滚动模式使用固定缩略图高度，轮播模式使用固定轮播高度；真实图片走 `ThumbnailStripView` 按需加载缩略图，占位引导图片走同一尺寸合同。图片裁切使用 `scaledToFill + clipShape`，所以不同原图比例只影响缩略图裁切内容，不改变时间轴坐标。首页气泡图片区保持 hit testing，图片上的横向手势优先用于缩略图滚动或轮播切换；非图片区仍由 `List` 行级 `.swipeActions` 承担删除。

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

`MomentEditorView` 是任务卡片栈第一层。编辑器使用自绘 `EditorSheetChrome` 承载取消、日期 chip、时间 chip 和保存按钮，不依赖 `NavigationStack.toolbar` 的系统导航栏高度来决定内容起点；正文区仍用 `TaskPageScrollView`，但通过 `EditorLayout.contentInsets` 使用编辑器专属紧凑顶部 inset，不改全局任务页 `TaskSurfaceMetrics.pageVerticalInset`。情绪、标签、日期和时间选择当前由 SwiftUI 代码实现为局部选择：

- 情绪行打开 `MoodPickerView`。
- 标签行打开 `TagPickerView`，只选择已有标签，不提供新增入口。
- 顶栏日期 chip 打开 `DatePickerSheetView`。
- 顶栏时间 chip 打开 `TimePickerSheetView`。
- 这些选择器都由局部 `.popover` 呈现，不进入 `AppRouter`。
- 日期使用系统 `.graphical` `DatePicker`。
- 时间使用系统 `.wheel` `DatePicker`。
- 选择后通过 `OccurredAtComposer` 合成 `occurredAt`，只改变日期或只改变时间。
- 没有额外确认按钮。

这条代码路径使用系统日期/时间控件，未为基础 picker 重做自定义控件。当前测试面覆盖日期和时间 popover 的打开/收起，并用 `OccurredAtComposerTests` 覆盖“只改日期保留时分秒 / 只改时分保留年月日和不可见秒”的合成语义。

## 设置与外观

`SettingsSheetView` 是根级第一层 sheet，内部使用 `NavigationStack + TaskPageScrollView`。根页不提供显式关闭按钮，依赖系统 sheet 下滑关闭；设置子页包括统计、标签、垃圾箱、语言、外观、关于，均在设置栈内 push 并保留系统返回；Pro 横幅使用设置内部局部 `.sheet(item:)` 打开 `ProPaywallView`。

任务页的响应式骨架收口在 `TaskContainerStyle.swift`：

```text
TaskSurfaceMetrics
  -> TaskPageScrollView
      -> TaskSurfaceSection
          -> TaskSurfacePanel
              -> TaskSurfaceRow / feature content
```

`TaskSurfaceMetrics` 定义任务页内容列的水平边距、最大可读宽度、分组间距、panel 圆角、panel padding 和 row 最小高度。`TaskPageScrollView` 负责 sheet 背景、滚动和底部安全余量；`TaskResponsiveContent` 只负责内容列居中、最大宽度和页边距，因此可被统计页等非 sheet 背景场景借用；`TaskSurfaceSection` 负责可选标题和 panel 边界；`TaskSurfacePanel` 只表达任务容器面板；`TaskSurfaceRow` 表达设置类行。用于 UI 验证的 section measurement identifier 是 1pt 透明边界标记，不覆盖整块内容，避免抢走按钮命中区域。

这套骨架只用于“系统任务空间”：设置根页、外观详情、编辑器输入面板、预览阅读卡片，以及统计/标签/垃圾箱的页边距基线。它不用于首页品牌画布、时间轴 Moment 气泡、筛选 popover、日期/时间 popover 或标签创建 sheet；这些对象各自保留自身语义。当前 Settings 的 Pro 横幅、设置分组、支持分组、关于分组共享同一内容列；Appearance 的模式、颜色、网格、图片分组共享同一内容列；Editor 的文本输入 panel 和添加照片 CTA 共享同一内容列；Preview 的阅读内容也进入同一任务页滚动骨架。

`TagManageView` 是当前标签新增、重命名、删除的唯一管理入口。右上“+”在打开 `TagCreateSheetView` 前经 `QuotaService` 做标签额度闸门，超额时打开 `ProPaywallView`；`TagCreateSheetView` 在真正创建新标签前再次复核标签额度，避免表单打开后数量变化造成越额写入。`TagCreateSheetView` 使用设置子页上的局部 `.sheet(item:)` 呈现为第二层任务卡片，当前为 `.large` detent 的系统 page sheet，内容是居中的“# 标签名称 / 输入框 / 整行保存 / 取消”纵向表单；重命名态复用同一表单骨架并预填原名。列表行点击进入重命名，左滑使用统一的系统 `.swipeActions(allowsFullSwipe: true)` 展示删除按钮并支持 full swipe。删除成功后调用 `TimelineModel.discardFilterTag` 清理当前筛选中可能残留的标签 id。

`AppearanceThemeView` 已有四组设置：

```text
模式
颜色
网格
图片
```

这些选项通过 `ThemeManager` 即时更新并持久化到 `AppearanceStore`。保存失败和偏好修正提示使用页内文本，不走全局 alert。

当前外观设置的落地边界：

- `ThemeManager` 是运行时主题 token 消费入口，并暴露 `tokens: AppThemeTokens` 作为当前模式 + 主色解析后的稳定 token。定义层已拆为 `BrandCanvasPalette`（首页品牌画布）、`MemoryObjectPalette`（气泡/热力图等记忆对象）、`TaskContainerPalette`（sheet/设置/编辑等任务容器）、`AccentPalette`（行动强调主色及其派生前景）、`MoodPalette`（心情色数据语义）和 `FixedIntentColor`（危险、商业固定、图片查看器媒体色）。兼容门面已移除，新增颜色消费必须走 `ThemeManager`、`AppThemeTokens` 或对应 palette。
- 业务 view 不直接新增十六进制色值，P2b 触达范围内的二级文字、弱提示、强调色前景、选中弱填充、禁用强调填充、热力图月份高亮、首页纹理色、自定义背景遮罩、顶部 chrome 叠色、热力图分隔线、预览外框、商业固定色和图片查看器固定媒体色均经 `theme.*` 消费。
- 模式、主色会影响已接入 `ThemeManager` 的背景、文字、气泡、chip、热力图空格、顶栏图标描边、首页背景纹理、行动强调前景和外观页分组缩略卡等。亮色不是暗色反相：首页仍使用轻灰紫画布，任务 sheet 使用 iOS 分组浅色体系，首页气泡和 sheet panel 不互相复用。
- 心情色通过 `theme.moodColor(_:)` 解析，不读取主色。
- 危险色通过 `theme.danger` 解析，不读取主色。
- `ProPaywallView` / `AboutView` 使用固定商业 token，并在本页局部注入 `.light` color scheme：浅色背景、浅色行/面板、固定红和固定商业文字不跟随用户主色或暗/亮模式，也不被设置任务容器的暗色环境污染。Paywall 的月订阅 / 终身买断结构仍按当前 StoreKit 契约展示；双方案视觉样式是否继续改造仍归 Paywall 专项裁决。
- `ImageViewerView` 使用固定媒体 token：沉浸黑底、白色 chrome 和黑色 chrome scrim，不跟随主题主色。
- `TaskContainerStyle` 是任务容器层的 SwiftUI 封装：设置、外观、语言、标签、垃圾箱、编辑器、预览和筛选等任务面板统一注入 `theme.colorScheme`、导航栏色彩方案和 `theme.accent`。任务内容列使用 `TaskPageScrollView` / `TaskSurfacePanel` 表达响应式宽度与 panel 语义；统计页只借用 `TaskResponsiveContent` 的内容列，不继承 sheet 背景；仍需系统行级能力的标签和垃圾箱列表保留 `List` / `.swipeActions`，通过 `taskListContentFrame()` 和共享 row inset 对齐同一最大宽度基线。这样避免系统默认浅色 grouped list 在暗色主题下盖住正确文字色，也避免不同任务页各自写死宽度。
- `SettingsNavigationChrome` 是设置流专属导航外壳，不并入通用任务容器：设置根页保留系统默认标题样式，设置详情页统一 `.inline` 居中系统标题；导航栏背景保留 SwiftUI / UIKit 系统 scroll-edge 行为，顶部透明、滚动压入内容后由系统 material 接管，不自绘标题、不写死 `UINavigationBarAppearance` 或导航栏背景色。`MoodStatsView`、`TagManageView`、`TrashView`、`LanguageSettingsView`、`AppearanceThemeView`、`AboutView` 都挂同一详情页导航契约；`AppearanceThemeView` 的系统标题与设置入口统一为「外观主题」。
- 设置栈内的 `TagManageView`、`TrashView`、`LanguageSettingsView` 已归入任务容器语义，背景使用 `sheetBackground`，行/面板使用 `sheetPanelBackground`，文字使用 `primaryText` / `secondaryText`，不再复用首页品牌画布和气泡 token。
- `backgroundTexture` 已驱动首页主场景背景，`HomeSceneBackgroundView` 统一渲染网格线、点阵、无和自定义图片；作用范围包括时间轴背后区域、顶部 chrome 展开态和首页热力图上下文，不作用于设置页、编辑器 sheet、气泡卡片或其它页面。
- 自定义背景图片由 `AppearanceThemeView` 通过系统 `PhotosPicker` 选择，`ThemeManager` 在后台压缩后写入 `AppearanceStore` 暴露的 Application Support 固定文件；写入成功后才切到 `.customImage`，写入失败不改变当前背景。UI 测试下使用 `-uiTestBackgroundImageInjection` 暴露调试注入按钮。
- `imageDisplayMode` 已有 UI、状态和持久化，并驱动时间轴气泡图片区在横向缩略图布局和轮播布局之间切换；它只改变照片展示行为，不改变主题颜色语义。
- `AppearanceThemeView` 使用 `TaskPageScrollView` 任务内容列和自适应 `LazyVGrid` 分组骨架。模式区两张卡是当前外观状态在暗/亮模式下的总览预览，会同时体现当前背景纹理/自定义图片、导航文字层、FAB/主色和模式色板；颜色区使用响应式 swatch 网格，不允许固定宽度溢出屏幕；网格区的选项卡只表达纯背景纹理效果，不再展示 FAB 或导航元素；图片区只表达滚动/轮播展示差异。外观页组件消费 `ThemeManager` 和 `AppThemeTokens.resolve`，但不进入 `AppRouter`，也不把首页品牌画布、气泡卡片和 sheet panel 混成同一个容器。

## 与设计层的已知漂移

| 漂移 | 当前事实 | 当前影响 |
| --- | --- | --- |
| 亮色心情色 | 亮色下除 `.normal` 外仍沿用暗色推导值。 | 不影响主色独立性；亮色效果缺少独立取色事实。 |

## P2b 验证事实

2026-07-08 已运行：

```sh
./scripts/test.sh --only MoodmentsTests/ThemeManagerTests
./scripts/test.sh --only MoodmentsUITests/ThemeSwitchUITests/testSwitchingModeUpdatesModeOptionCardRendering
./scripts/test.sh --only MoodmentsUITests/ThemeSwitchUITests
./scripts/verify.sh
```

结果：`ThemeManagerTests` 执行 7 个测试、0 失败，覆盖自定义背景图写入/修正、五层 token 暗/亮取值、主色派生前景矩阵和商业固定色独立性；`ThemeSwitchUITests` 执行 10 个测试、0 失败，覆盖切换亮/暗、主色、主色 swatch 不溢出屏幕、外观页分组同宽、主色驱动模式总览同步、背景纹理、自定义背景图、图片展示模式，以及设置/外观任务容器在 sheet 已挂载时跟随模式更新；最终 `./scripts/verify.sh` 全部通过。

## P0 验证事实

2026-07-07 已运行：

```sh
./scripts/test.sh --unit
./scripts/test.sh --ui
```

结果：全量单元测试和 UI 测试通过。后续新增测试后，具体测试数量以当次脚本输出为准，不在 current 文档中固化旧数量。

2026-07-07 追加运行：

```sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsTests/MomentCardLayoutTests
./scripts/test.sh --only MoodmentsTests/TimelineGeometryTests
./scripts/test.sh --only MoodmentsTests/TimelineRailVisibilityTests
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testSwipeDeleteMovesToTrash
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testSwipingOnTimelineImageDoesNotTriggerDelete
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testSwipingOnTimelineCarouselImageDoesNotTriggerDelete
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testPreviewIsCardNotPush
./scripts/test.sh --only MoodmentsUITests/LocateFilterUITests/testFilterAbsentMoodShowsEmptyStateThenMarkerRemovalRestoresRecords
./scripts/test.sh --only MoodmentsUITests/TimelineEmptyStateUITests/testEmptyStateShowsThreeGuidedMoments
./scripts/build.sh
./scripts/lint.sh
```

结果：`MomentCardLayoutTests` 执行 4 个测试、0 失败；`TimelineGeometryTests` 执行 13 个测试、0 失败；`TimelineRailVisibilityTests` 执行 4 个测试、0 失败，覆盖筛选空态不渲染孤立轨道、真实记录和未筛选引导记录仍渲染轨道；四条 `DeleteRestorePurgeUITests` 定向 UI 用例均通过，覆盖首页左滑软删除进垃圾箱、横向缩略图和轮播图片区横向手势不触发行级删除、非图片区仍可露出系统删除按钮，以及预览卡片不是 push 页面；筛选空态 UI 和未筛选引导空态 UI 均通过。`build` 通过；`lint` 通过并保留既有 warning。

2026-07-08 追加运行一次 P0 视觉取证 UI 流程，截图写入 `/private/tmp/heatmoment-p0-visual/`：

```sh
./scripts/run.sh
./scripts/gen.sh
./scripts/test.sh --only MoodmentsUITests/P0VisualAuditCaptureUITests/testCaptureP0VisualAuditStates
./scripts/verify.sh
```

首次截图审计发现两个实现偏差：热力图年份因 SwiftUI 文本本地化显示为 `2,026`，以及热力图展开并滚动定位后顶部上下文区域有时间轴内容透出。代码修正后重新运行同一取证流程，结果通过。当前截图证据覆盖暗色主页、热力图展开、日期定位、筛选与定位标记并存、左滑删除露出系统删除按钮、亮色主页。审计结论是：节点中心、气泡尾巴和时间轴竖线形成明确绑定；热力图仍属于主页顶部上下文，不是独立漂浮卡片；系统 `.swipeActions` 的轻扫状态满足“阅读单元横向移走、场景轨道保持连续”的 P0 视觉边界。

最终阶段验收运行 `./scripts/verify.sh`，结果全部通过：lint 完成、构建通过、单元测试执行 132 个测试（4 个跳过）且 0 失败、UI 测试执行 37 个测试且 0 失败。lint 仍打印仓库既有 warning，但未阻塞验证。

当前 P0 视觉验收仍有两个非阻塞边界：截图取证是人工视觉审计，不是像素级 snapshot 断言；不同真机尺寸和未来动态内容仍需随对应阶段做抽查。

## Flutter 版只作为语义输入

原 Flutter 项目只作为产品语义输入；SwiftUI current 事实以本仓库 `Sources/Moodments/` 与 `Tests/` 为准。Flutter 中的 `showCupertinoSheet`、`GlobalKey + ScrollController`、自定义气泡 shape、Flutter picker 组合、开发者皮肤轴等都不是 SwiftUI 必须照搬的实现细节。
