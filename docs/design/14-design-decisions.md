# 14 架构与设计决策记录（ADR）

> **本文职责**：记录经生产就绪评审后拍板的关键架构/交互决策，供开发追溯「为什么这么定、否决了什么」。每条决策一旦「已采纳」即为开发准绳，落地细节见对应专章。格式：决策 / 背景 / 备选与否决理由 / 影响。
>
> 记法约定：本文的「效果命名」采用业界通用名（英文为主）+ 可搜索关键词，便于开发直接检索成熟实现，而非从零造轮子。
>
> **上游依据**：本文浮层层级 / 呈现相关决策（ADR-003 / ADR-006 / ADR-007）依据 `product-mental-model.md` 公理 3（删除是生命周期）、公理 4（两种本质不同的浮层层级）、公理 5（永不离开主场景）；若与公理冲突以公理为准。

---

## ADR-001 架构范式：`@Observable`-based MVVM

- **状态**：已采纳
- **决策**：采用 iOS 17 Observation 宏的 MVVM——View 持有 `@Observable` view model 用 `@State`，跨层依赖用 `@Environment`，列表用 `@Query` 直接驱动。
- **背景**：中小型单页 App，需要官方推荐、低样板、可测试的状态组织方式。
- **备选与否决**：
  - **TCA（The Composable Architecture）**：严格单向数据流、极强可测试性；否决理由——样板多、学习曲线陡、运行时开销，本 App 规模不值得。可搜索：`swift composable architecture`。
  - **极简 MV（无 ViewModel）**：最简；否决理由——编辑器/订阅等复杂页面逻辑会泄漏进 View，难测试。
- **影响**：全局；**禁止 `@Observable` 与旧 `ObservableObject` 混用同一数据流**（依赖追踪机制不同，混用刷新时机难推理）。可搜索：`swiftui @Observable macro`、`observation framework`。

## ADR-002 导航：集中式 `AppRouter` 路由 model

- **状态**：已采纳
- **决策**：跨页导航意图（首页 push 栈、根级 sheet、应用锁）集中到一个 `@MainActor @Observable` 的 `AppRouter`，Environment 注入；页面局部状态（首页定位/筛选/热力图展开）不进 Router。
- **背景**：单页 + 多模态层的 App，需要可深链、可状态恢复、导航意图集中可推理。
- **备选与否决**：
  - **分散 `.sheet(item:)` / `@State`（就近驱动）**：最简；否决理由——深链、"返回到指定层级"、状态恢复难实现，导航状态散落难追踪。（注：叶子级弹层仍可局部驱动，见 ADR-003 的层叠协作说明。）
- **影响**：新增 `Navigation/AppRouter.swift`；`Features/*` 只发意图不各自持久化导航状态。可搜索：`swiftui NavigationStack NavigationPath router`、`unidirectional navigation swiftui`。

## ADR-003 模态呈现：区分「任务卡片栈」与「就地选择层」两类浮层（依公理 4）

- **状态**：已采纳（依 `product-mental-model.md` 公理 4）
- **效果命名**：
  - **任务卡片栈** = iOS **Sheet Presentation / Page Sheet**（UIKit `UISheetPresentationController`），多层叠加时底层卡片下沉缩小变暗的形态社区称 **Stacked Sheets / Cascading Page Sheets / Card Stack Modal**。出处：iOS 13 卡片式模态 + iOS 15 detents + iOS 16.4 SwiftUI presentation 修饰符。
  - **就地选择层** = 不入任务卡片栈的局部选择呈现；首页筛选使用 half-sheet，编辑字段选择使用 popover。
  - **就近浮窗** = 字段选择用的 **Popover**（锚定触发元素、带指向尖角、尺寸自适应，`.popover` + `presentationCompactAdaptation(.popover)`）。
- **决策**：**两种本质不同的浮层层级不可混用**——
  1. **任务卡片栈（承接完整任务）**：用系统 `.sheet`（page sheet），**背景下沉、上一层缩小、进入层级栈**，由 Router 的 `.sheet(item:)` 驱动；**卡片层叠下沉是系统默认行为**（sheet 上再 present sheet 即自动层叠），不手写动画、不引第三方库。成员：新建/编辑、**单条预览（弹出阅读卡片，见 ADR-007）**、设置及其子页、Pro 权益、新建标签。
  2. **就地选择层（承接条件/字段调整，不入任务卡片栈）**：`FilterPanelView` 是首页就地筛选 half-sheet；`MoodPickerView`、`TagPickerView`、`DatePickerSheetView`、`TimePickerSheetView` 是编辑字段就近浮窗。筛选 half-sheet 不 push、不进 `AppRouter.rootSheet`，选择即时生效且不自动关闭；字段 popover 锚定触发元素、带指向尖角、尺寸自适应，跨设备保持浮窗形态（见 ADR-006）。
  - `.fullScreenCover` 仅用于图片查看器与隐私锁（无层叠语义）；年度热力图属于首页顶部上下文区，不入任务卡片栈，也不作为独立漂浮层。
  - **层叠与集中 Router 协作**：任务卡片栈第一层绑 `router.rootSheet`；第二/三层（编辑器→Paywall、设置子页→新建标签）由该 sheet 的局部子状态驱动其 `.sheet(item:)`，呈现层叠由系统完成。**就地选择层不进路由栈、不由 `rootSheet` 驱动**，由触发处的局部状态驱动。
- **备选与否决**：
  - **第三方 sheet 库（类 `wolt_modal_sheet` 的 Swift 实现 / FittedSheets）**：否决理由——只有"同一 sheet 内多步骤切换 + 高度过渡动画"才需要，本 App 用不上，徒增依赖。
  - **自定义转场 / 手写 `Transform` 缩放下沉**：否决理由——系统已自带该形态，手写反而与系统手势冲突、难维护、易破坏 HIG 一致性。
  - **所有浮层统一为 page sheet（含编辑字段选择也走半高 sheet）**：否决理由——违反公理 4，把"就地选择"全部错误地挤入任务卡片栈，破坏"永不离开主场景"的心智。首页筛选 half-sheet 是就地精炼的局部选择层，不是任务卡片 sheet。
- **影响**：消除文档里"popover / 内嵌浮层""半高 sheet / popover"的二义。可搜索：`swiftui sheet presentationDetents`、`presentationCornerRadius`、`presentationBackground`、`ios page sheet stacked`、`swiftui popover presentationCompactAdaptation`。

## ADR-004 最低系统版本：iOS / iPadOS 17.0

- **状态**：已采纳
- **决策**：最低 iOS 17.0。
- **背景**：与 SwiftData、`@Observable` 起点一致；`presentationDetents`(16.4+)、`presentationBackground`(16.4+)、`@Observable`(17) 均可用。
- **备选与否决**：**iOS 18+**——可用更新的 presentation/动画 API 与 SwiftData 改进，但放弃部分老设备用户，当前收益不足以抵消覆盖面损失。
- **影响**：可放心使用 iOS 17 全部 SwiftData / Observation / presentation API。

## ADR-005 并发模型：`@MainActor` + `ModelActor` + `.task(id:)`

- **状态**：已采纳
- **决策**：UI 层 / view model / Router / ThemeManager 标 `@MainActor`；SwiftData 写入/批量/计数走后台 `ModelActor`；异步加载用 `.task(id:)` 随 view 生命周期自动取消；共享可变状态用 `actor` 封装；Service 接口 `async`。
- **背景**：文档原先未定义并发模型，属生产阻塞缺口。`ModelContext` 有线程约束，主线程重写入会卡 UI；异步任务不随 view 取消会"过期响应写错 UI"。
- **备选与否决**：**全部主线程 + `DispatchQueue` 手动切换**——否决理由——与 async/await 混用刷新时机难推理，Swift 6 严格并发下告警密集。
- **影响**：跨隔离域只传值类型（如 `Moment.ID`），不传 `@Model` 引用。可搜索：`swiftdata modelactor background`、`swiftui .task(id:) cancellation`、`@MainActor swiftui`。

## ADR-006 就地选择：筛选 half-sheet 与字段锚定浮窗（依公理 4）

- **状态**：已采纳（**取代原 ADR-006「紧凑弹选 iPhone 半高 sheet / iPad popover」，旧决策 superseded**）
- **决策**：就地选择层按内容重量分两种呈现：
  - **首页筛选（`FilterPanelView`）**：使用半屏 bottom sheet（`.sheet` + `.presentationDetents([.medium, .large])`）。它从首页收起态标题/筛选入口打开，语义是"留在主页、调整当前时间轴内容"，不是导航式任务页；不 push、不进 `AppRouter.rootSheet`、不进入任务卡片栈。筛选即时作用于时间轴、上下文标记和热力图口径，选择条件后 sheet 不自动关闭，用户通过「完成」或系统下滑手势关闭。
  - **编辑字段选择（`MoodPickerView`、`TagPickerView`、`DatePickerSheetView`、`TimePickerSheetView`）**：保持就近浮窗（popover 语义）：锚定触发元素、带指向尖角、尺寸自适应、背景不下沉、不缩小、不进层级栈。跨设备都保持锚定浮窗形态，iPhone 上不降级为下沉的半高 sheet（用 `.popover` + `presentationCompactAdaptation(.popover)` 强制保持 popover，而非默认降级）。
- **筛选语义**：心情单选，可切回全部心情；标签多选，多个标签采用 AND 语义；「清除全部」同时移除心情和标签筛选。筛选只改变"看哪些记录"，热力图只改变"定位到哪个时间位置"，二者可同时存在但不可合并。
- **背景**：依 `product-mental-model.md` 公理 4，任务卡片栈与就地选择层是两种本质不同的浮层层级。首页筛选承载多个条件的连续调整，固定窄宽 popover 不利于扫读和多选；half-sheet 是 SwiftUI 成熟组件下的局部选择容器，但不具备任务卡片栈语义。编辑页日期/时间/心情/标签仍是字段级短选择，需保持锚定浮窗。
- **影响**：`08-architecture.md` §2 与本 ADR-003 对齐；`02-information-architecture.md`、`04-screen-specs.md` 对应页面呈现按"筛选 half-sheet / 字段 popover"定稿。可搜索：`swiftui sheet presentationDetents medium large`、`swiftui popover presentationCompactAdaptation popover`、`anchored popover iphone`。

## ~~ADR-006（旧）紧凑弹选：iPhone 半高 sheet / iPad popover~~ `[SUPERSEDED]`

- **状态**：已作废（被上方新 ADR-006 取代，依公理 4）
- **原决策（作废）**：情绪/标签/筛选"从某行展开的紧凑选择"，iPhone 用半高/自适应 `.sheet`（`.presentationDetents`），iPad 用 `.popover`，用 `.presentationCompactAdaptation` 让 iPhone 降级为 sheet。
- **作废理由**：把"就地选择"当成"完整任务"处理——iPhone 上下沉背景、进入层级栈，违反心智模型公理 4（两种浮层层级不可混用）与公理 5（永不离开主场景）。就近选择应保持锚定浮窗、背景不下沉、不入栈。

## ADR-007 预览 = 任务卡片（弹出阅读卡片），非 push 页面跳转（依公理）

- **状态**：已采纳（依 `product-mental-model.md` 公理 4/5；预览无独立截图，属产品逻辑推导，非真机观测）
- **决策**：点一条时刻查看，是在当前时间轴**之上弹出一张阅读卡片**（进任务卡片栈，page sheet 语义），**不是 push 到另一个页面**。`MomentPreviewView` 由 Router 的 `rootSheet`（`.preview(Moment.ID)`）驱动，从卡片再进编辑器即形成第二层卡片层叠；关闭卡片回到时间轴原滚动位置。
- **背景**：心智模型将时刻定义为"被阅读时以一张浮起的阅读卡片完整呈现"，且公理 5 要求"永不离开主场景"。push 页面跳转会离开时间轴主场景、与"临时任务在主场景之上展开"的语义不符；预览本质是一个"临时、可层叠、完成即回主场景"的完整任务，归属任务卡片栈。
- **备选与否决**：
  - **`NavigationLink` push（首页栈内）**（原文档方案）：否决理由——离开主场景、非卡片层叠语义，违反公理 4/5；预览作为完整阅读任务应入卡片栈。
- **影响**：`08-architecture.md` §2.2 映射表、§3 Router（`MomentPreview` 归入 `rootSheet`、不再进 `homePath`）、`02-information-architecture.md` 导航图均按此定稿。

---

## 数据模型生产隐患修正（评审附带）

以下为评审发现、已在 `07-data-persistence.md` 修正或标注的数据层隐患，非架构决策，记录备查：

1. **去除 `Moment.id` 的 `@Attribute(.unique)`**：CloudKit 下 `.unique` 不生效（文档第 2 节约束自陈），保留会误导；唯一性靠 UUID 值本身保证。
2. **CloudKit 关系可选性**：SwiftData 接 CloudKit 要求关系可选，`tags`/`images` 关系声明在接入 CloudKit 时复核。
3. **缩略图缓存与图片压缩**：`Caches/thumbnails` 需补失效/清理策略与图片压缩规格（HEIC→JPEG、目标体积），见 `07-data-persistence.md` 与 `12-quality-assurance.md`。
