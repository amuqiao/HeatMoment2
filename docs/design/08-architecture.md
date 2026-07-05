# 08 App 架构与工程组织

> **本文职责**：面向后续开发，从全局视角综合提炼「时刻」App 的 SwiftUI 架构——技术基线、架构范式、导航呈现机制、集中路由、状态管理、并发模型、分层与限额校验落点，以及建议的模块划分与 Xcode 工程目录结构。本章是**综合视图**，各要点细节以对应专章为准：页面级交互见 `04-screen-specs.md`、视觉与主题见 `05-design-system.md`、领域枚举与限额见 `06-domain-model.md`、数据实体与持久化见 `07-data-persistence.md`、iCloud 同步见 `09-icloud-sync.md`、隐私锁见 `10-security-privacy.md`、Pro/StoreKit 见 `11-monetization.md`、用户流程见 `03-user-flows.md`、开放问题见 `13-open-questions.md`。**本章涉及的架构选型决策记录见 `14-design-decisions.md`（ADR）。**

---

## 0. 技术基线与架构范式（已评审拍板）

以下为经生产就绪评审后**锁定**的技术决策，开发按此执行，不再二选一（决策理由与备选见 `14-design-decisions.md`）：

| 项 | 决策 | 说明 |
|---|---|---|
| 最低系统 | **iOS / iPadOS 17.0** | 与 SwiftData / `@Observable` 起点一致；`presentationDetents`(16.4+)、`@Observable`(17) 均可用 |
| 架构范式 | **`@Observable`-based MVVM** | View 持有 `@Observable` model 用 `@State`，跨层用 `@Environment`；列表用 `@Query` 直接驱动；**不引 TCA**；**禁止 `@Observable` 与旧 `ObservableObject` 混用同一数据流** |
| 导航/模态状态 | **集中式 `AppRouter`（`@Observable`，Environment 注入）** | 全局导航意图（根级 sheet、push 栈、覆盖层、应用锁）集中到一个可观察路由 model；见第 3 节 |
| 浮层层级 | **两类：任务卡片栈（page sheet 层叠）+ 就近浮窗（popover，不下沉/不入栈）** | 完整任务用可层叠的任务卡片栈（卡片下沉靠系统默认、不手写动画/第三方库）；就地选择用锚定就近浮窗；预览=弹出阅读卡片；见第 2 节与 `14-design-decisions.md` ADR-003/006/007 |
| 并发 | **Swift Concurrency + `@MainActor` + SwiftData `ModelActor`** | UI 层 `@MainActor`；写入/批量/计数在后台 `ModelActor`；异步加载用 `.task(id:)`；见第 5 节 |
| 持久化 | **SwiftData + CloudKit 私有库** | 见 `07-data-persistence.md`、`09-icloud-sync.md` |

三条最容易被实现者搞错、必须在架构层锁死的约束：
1. **热力图定位 ≠ 筛选**：`heatmapFocusDate` 与 `activeFilter` 必须是两个独立状态源（详见第 4 节）。
2. **额度计数 ≠ 列表展示**：Moment 10 篇计数含垃圾箱内软删除记录，时间轴列表只查未软删除记录，二者是不同查询（详见 `07-data-persistence.md`）。
3. **限额校验落在 Service 层**：UI 不自行判断额度，只消费校验结果（详见第 6 节）。

---

## 1. 架构总览

「时刻」是**单页信息架构 + 本地优先 + 无自建后端**的个人时刻记录 App：
- 根体验只有一个一级页面 `TimelineHomeView`，其余功能（新建、预览、筛选、热力图、设置及其子页）都从首页展开为临时上下文任务，完成后回到时间轴。
- 数据边界收敛在「设备本地 SwiftData 存储 + 用户个人 iCloud 私有数据库」内，不引入账号体系、不引入自建服务器；订阅授权由 Apple StoreKit 承担。
- UI 层以 SwiftUI `@Query` 数据驱动 + `@Observable` view model，业务规则（限额、Pro 判定、同步、生物识别）下沉到 Service/Repository 层，UI 只消费结果；跨页导航意图集中到 `AppRouter`。

---

## 2. 导航与模态呈现（统一规范）

### 2.1 两类本质不同的浮层层级 `[设计决策，已评审拍板；依据 product-mental-model.md 公理 4]`

App 采用「首页为根的单 `NavigationStack` + 两类浮层 + 沉浸全屏 + 覆盖层」的呈现体系。**关键在于区分两种本质不同的浮层层级（公理 4），不再用旧的"iPhone 半高 sheet / iPad popover"统一方案**：

1. **任务卡片栈（承接完整任务）**：用系统 `.sheet`（page sheet），**背景下沉、上一层缩小、进入层级栈**（系统 page sheet 层叠语义），由 `AppRouter` 的 `.sheet(item:)` 驱动（不用散落的多个 bool，避免组合爆炸）。成员：新建/编辑、**单条预览（弹出阅读卡片）**、设置及其子页、Pro 权益、新建标签。
   - **卡片层叠下沉效果 = 系统默认行为**：在一个 page sheet 之上再 present 一个 `.sheet`，系统自动把底层卡片下沉、缩小、变暗；逐层关闭逐层浮回。**禁止手写 `Transform`/缩放动画模拟，禁止用 `.fullScreenCover` 冒充可层叠的模态**（业界称 Stacked Sheets / Cascading Page Sheets，见 `14-design-decisions.md` ADR-003）。
2. **就近浮窗（承接就地选择）**：**锚定触发元素、带指向尖角、尺寸自适应、背景不下沉、不缩小、不进层级栈**（popover 语义）。成员：标签筛选、心情筛选、日期选择、时间选择。**跨设备都保持锚定浮窗形态，iPhone 上不降级为下沉的半高 sheet**（依公理 4，见 `14-design-decisions.md` ADR-006）。
3. **`.fullScreenCover` 只用于「无层叠语义的沉浸全屏」**：图片查看器、隐私锁两处。
4. **覆盖层（overlay）用于「非模态的顶部展开」**：年度热力图。

**预览 = 弹出阅读卡片（进任务卡片栈），不是 push 页面跳转**（依公理，预览无独立截图，属产品逻辑推导）。

### 2.2 View → 呈现机制映射（定稿）

| View ID | 呈现机制（定稿） | 说明 |
|---|---|---|
| `TimelineHomeView` | 根页面（`NavigationStack` root） | 唯一一级页面 |
| `MomentEditorView` | 任务卡片栈（`.sheet` page sheet，Router 驱动） | 内含独立 `NavigationStack` 承载「取消/保存」顶栏；新建/编辑复用 |
| `SettingsSheetView` | 任务卡片栈（`.sheet` page sheet） | 内含独立 `NavigationStack`，子页在栈内 push |
| `ProPaywallView` | 任务卡片栈（`.sheet` page sheet） | 三类触发来源共用；从编辑器/设置之上弹出时即形成第二层卡片层叠 |
| `MomentPreviewView` | 任务卡片（弹出阅读卡片，入卡片栈） | 点卡片弹出阅读卡片，非 push；关闭回到时间轴原滚动位置 |
| `YearHeatmapView` | `ZStack` overlay（覆盖层） | 顶部展开、背景半透明，非模态；X 收起并保留时间轴状态 |
| `FilterPanelView` | 就近浮窗（锚定、带尖角、不下沉背景、不入栈；跨设备保持浮窗，不降级半高 sheet） | 就地选择即时应用，无「确认」按钮 |
| `MoodPickerView` | 就近浮窗（锚定、不下沉、不入栈；跨设备保持浮窗） | 从编辑器情绪行展开 |
| `TagPickerView` | 就近浮窗（锚定、不下沉、不入栈；跨设备保持浮窗） | 从编辑器标签行展开，支持多选 |
| `TagCreateSheetView` | 任务卡片栈（`.sheet` 自适应高度 detent，视觉居中卡片） | 从 `TagPickerView` 或 `TagManageView` 打开（第二/三层卡片层叠） |
| `DatePickerSheetView` / `TimePickerSheetView` | 就近浮窗（锚定、不下沉、不入栈；跨设备保持浮窗，不降级半高 sheet） | 从编辑器顶栏 chip 打开，选后立即回填 |
| `ImageViewerView` | `.fullScreenCover`（全屏） | 无层叠语义，沉浸浏览 + 缩放/翻页 |
| `MoodStatsView` / `TagManageView` / `TrashView` / `AppearanceThemeView` / `AboutView` | 设置栈内 `NavigationLink` push | 设置 sheet 内部的二级页 |
| `PrivacyLockView` | 应用级 `.fullScreenCover` | 无手势关闭，验证通过前不渲染任何内容 |

导航拓扑（触发关系）：
- 首页 → 编辑器（悬浮按钮 / 限额未超）、预览（点卡片）、热力图（左侧日历图标）、筛选（收起态标题「时刻 ⌄」，大标题态不可点）、设置（右侧六边形图标）。
- 编辑器 → 情绪/标签/日期/时间各弹层；标签选择 → 新建标签弹窗；保存或触达免费上限 → Paywall（第二层卡片层叠）。
- 预览 → 编辑器（编辑入口）、图片查看器（点图片）。
- 设置 → Pro 横幅（Paywall）、心情统计、标签管理、垃圾箱、外观主题、关于。
- App 生命周期：冷启动 / 回前台且面容解锁开启 → `PrivacyLockView`，验证通过后进入首页。

各页面具体内容/状态/无障碍见 `04-screen-specs.md`；视觉方案见 `05-design-system.md`。

---

## 3. 集中路由 `AppRouter` `[设计决策，已评审拍板]`

导航意图集中到一个 `@Observable` 路由 model，通过 `@Environment` 注入全树；**页面局部数据状态（如首页的定位/筛选）不进 Router**，由对应 feature 的 view model 持有（见第 4 节）。Router 提供 source of truth，具体层叠呈现交给系统 page sheet。

```swift
@Observable
final class AppRouter {
    // 首页 push 栈（NavigationStack root 的 path）——预留给真正的 push 型路由
    var homePath: [HomeRoute] = []

    // 根级模态第一层（任务卡片栈，由首页发起）——用 item 驱动 .sheet(item:)
    // 预览是「弹出阅读卡片」而非 push，故归入任务卡片栈（rootSheet），不进 homePath
    var rootSheet: RootSheet?               // .preview / .editor / .settings / .paywall（筛选是就近浮窗，不在此）

    // 覆盖层与应用级层
    var isHeatmapPresented = false          // YearHeatmap overlay
    var fullScreenCover: FullCover?         // .imageViewer(MomentImage.ID) 等
    var isLocked = false                    // 隐私锁遮罩，scenePhase 驱动
    // 注：就近浮窗（标签/心情筛选、日期/时间选择）是锚定的局部浮层，
    //     不进路由栈、不由 rootSheet 驱动，由触发处的局部锚定状态就近驱动（见下）。
}

enum HomeRoute: Hashable { /* 预留：真正的 push 型路由 */ }
enum RootSheet: Identifiable { case preview(Moment.ID), editor(EditorMode), settings, paywall(PaywallTrigger); /* id... */ }
enum EditorMode { case create, edit(Moment.ID) }
enum PaywallTrigger { case banner, quotaMoment, quotaPhoto, quotaTag, restore }
enum FullCover: Identifiable { case imageViewer(momentID: Moment.ID, index: Int); /* id... */ }
```

**两类浮层如何与集中 Router 协作**（关键，避免实现者困惑）：
- **任务卡片栈·第一层**（预览/编辑器/设置/Paywall 由首页发起）：绑定 `router.rootSheet`，`TimelineHomeView` 上 `.sheet(item: $router.rootSheet)`。预览是弹出的阅读卡片（`.preview`），进卡片栈而非 push。
- **任务卡片栈·第二/三层**（编辑器→Paywall、设置子页→新建标签）：由**该 sheet 内容视图自身持有的局部子状态**驱动其 `.sheet(item:)`（或收敛到 Router 的分层字段，如 `editorSheet: EditorSheet?`），呈现上仍是「sheet 内再 present sheet」，**卡片层叠由系统自动完成**。集中 Router 只需负责「跨页级」意图，不必把每一个叶子弹层塞进一个巨型枚举。
- **就近浮窗**（标签/心情筛选、日期/时间选择）：**不进路由栈、不由 `rootSheet` 驱动**，是锚定触发元素的局部浮层，由触发处（时间轴筛选入口、编辑卡片对应字段）自身持有的局部锚定状态就近驱动；**背景不下沉、不缩小、不入层级栈**，跨设备保持锚定浮窗形态。
- **深链 / 状态恢复**（如通知点开某条 Moment）：解析为对 `homePath` / `rootSheet` 的赋值即可，这是选择集中 Router 而非分散 `@State` 的主要收益。
- **Router 属于 `@MainActor`**（导航即 UI 状态）。

---

## 4. 状态管理

### 4.1 关键状态源

| 状态 | 建议类型 | 归属 | 约束 |
|---|---|---|---|
| 导航/模态意图 | `AppRouter`（`@Observable`，Environment） | 全局 | 见第 3 节 |
| 热力图定位 | `heatmapFocusDate: Date?` | 首页 `TimelineModel`（`@Observable`） | 只影响 `ScrollViewReader` 滚动目标，**必须独立于筛选** |
| 标签/心情筛选 | `activeFilter: FilterCondition?` | 首页 `TimelineModel` | 只影响 `@Query` 谓词，**必须独立于定位** |
| 时间轴数据 | `@Query`（`occurredAt` 倒序 + 分页） | 时间轴/预览取数 | 只查 `isDeleted==false` |
| 聚合数据 | `@Query` + `#Predicate` 年份区间过滤 | 热力图 / 心情统计 | 存储层过滤，勿全量入内存 |
| 外观主题 | `ThemeManager` / `AppearancePreference`（Environment） | 全局呈现 | 乐观更新，见 4.3 |
| 订阅状态 | `SubscriptionStateCache`（本地缓存 + `Transaction` 核对） | Pro 态 UI 与放行判断 | 缓存仅供快速展示 |
| 隐私锁 | `AppRouter.isLocked`（`scenePhase` 驱动） | 应用级遮罩 | 立即锁定策略 |

### 4.2 定位与筛选必须双状态源（关键约束）

年度热力图定位与标签/心情筛选是**两件本质不同的事**：定位只改变滚动位置（不改变可见数据集合），筛选只改变可见数据集合（不改变滚动逻辑）。二者可同时存在、互不覆盖，工程上必须是两个独立状态变量（`heatmapFocusDate` / `activeFilter`，均在首页 `TimelineModel` 内），**严禁合并**。产品语义详见 `03-user-flows.md`。

### 4.3 主题注入与乐观更新

`AppearancePreference`（模式 / 主色 / 背景纹理 / 图片展示）通过 Environment 注入，由 `ThemeManager` 统一解析当前 `ColorScheme` 下的强调色语义。外观修改采用「先更新当前界面、再保存偏好」的乐观更新：点选后界面立即生效，保存失败时界面**不回滚**、仅提示。偏好写入需返回成功/失败结果供 UI 消费。主题参数矩阵、主色影响面、异常反馈文案见 `05-design-system.md`；结构见 `07-data-persistence.md`。

### 4.4 订阅状态

`SubscriptionStateCache` 只用于 UI 快速展示；任何「是否放行」的最终判断都以当次 `Transaction.currentEntitlements` 为准。启动/回前台用 `Transaction.currentEntitlements` 核对并订阅 `Transaction.updates` 实时刷新。判定与购买流程见 `11-monetization.md`。

---

## 5. 并发模型 `[设计决策，已评审拍板]`

采用 Swift Concurrency，隔离域清晰划分，避免数据竞争与"过期响应写错 UI"：

- **UI 层与 view model / `AppRouter` / `ThemeManager` 标 `@MainActor`**：所有 UI 状态更新在主线程；耗时工作 `await` 切后台，回来自动跳主线程，**不手动 `DispatchQueue.main.async` 与 async/await 混用**。
- **SwiftData 写入用后台 `ModelActor`**：`MomentRepository` / `TagRepository` 的增删改、批量、额度计数在 `ModelActor` 的后台 `ModelContext` 执行（`ModelContext` 有线程约束，主线程做重写入会卡 UI）；只读列表可用 `@Query` 主上下文。
- **异步加载一律 `.task(id:)`**：图片缩略图、聚合计算等随 view 生命周期自动取消，依赖变化用 `.task(id:)` 让旧任务自动取消重启；**不用 `onAppear { Task {} }`**（易漏取消）。
- **共享可变状态用 `actor` 封装**：如缩略图缓存、同步状态推导。
- **Service 接口 async**：`SubscriptionService` / `BiometricLockService` / `SyncStatusService` 暴露 `async` 方法。
- 面向 Swift 6 严格并发：非 `Sendable` 类型不跨隔离域传递（跨隔离传 `Moment.ID` 等值类型而非 `@Model` 引用）。

---

## 6. 分层与限额校验落点

「UI 层 → Service/Repository 层 → SwiftData 存储 / 系统框架」三层，业务规则不散落在 View：

```text
SwiftUI Views（消费结果，不做业务判断）+ @Observable view models + AppRouter（导航意图）
        │  调用 / 订阅（async）
        ▼
Service / Repository 层（业务规则唯一落点，写入走 ModelActor）
  ├── MomentRepository：增删改查、软删除/恢复/彻底删除、分页取数、额度计数
  ├── TagRepository：标签查重（应用层唯一性）、增删、额度计数
  ├── QuotaService：免费额度（10 篇 / 每篇 3 图 / 3 标签）+ Pro 判定校验
  ├── SubscriptionService：StoreKit 购买/恢复/核销码、entitlement 核对、缓存刷新
  ├── SyncStatusService：CloudKit 同步状态推导
  └── BiometricLockService：LocalAuthentication 生物识别/密码验证
        │
        ▼
SwiftData（@Model 持久化 + CloudKit）/ StoreKit / LocalAuthentication
```

**限额校验落点**：免费额度与 Pro 判定统一由 `QuotaService` / `SubscriptionService` 承担，UI 只消费「是否允许该操作」结果：

- 新建第 11 篇 Moment / 添加第 4 张照片 / 新建第 4 个标签时，Service 返回「超额」→ Router 弹出 `ProPaywallView` 拦截；购买成功后放行原操作，取消则回退到操作前状态（不产生半成品数据）。
- 额度计数口径（含垃圾箱软删除记录计入 Moment 上限）由 `MomentRepository` 保证，与时间轴展示查询分离。
- 限额数值唯一权威在 `06-domain-model.md`，Service 层引用而非各自硬编码。

Paywall 三类触发（设置横幅 / 限额阻断 / 恢复购买）UI 完全一致、只是关闭后回退目标不同，流程见 `03-user-flows.md` 与 `11-monetization.md`。

---

## 7. 建议的模块划分与 Xcode 工程目录结构 `[设计决策]`

```text
Moodments/
├── App/
│   ├── MoodmentsApp.swift          // @main，ModelContainer 装配、scenePhase、根遮罩
│   └── RootView.swift              // TimelineHome 装载 + AppRouter 注入 + PrivacyLock 遮罩
├── Navigation/
│   └── AppRouter.swift             // @Observable 集中路由（homePath / rootSheet / overlay / lock）
├── Models/                         // 领域模型与契约（见 06-domain-model.md）
│   ├── Mood.swift                  // 8 情绪枚举（持久化契约）
│   ├── FilterCondition.swift       // 筛选条件值类型
│   └── Quota.swift                 // 免费额度常量（引用唯一权威）
├── Persistence/                    // 数据实体与存储（见 07-data-persistence.md）
│   ├── Moment.swift / Tag.swift / MomentImage.swift   // @Model
│   ├── ModelContainer+Config.swift // ModelConfiguration / CloudKit 容器
│   ├── SchemaMigrationPlan.swift   // 版本化迁移
│   └── Repositories/               // ModelActor 后台仓库
│       ├── MomentRepository.swift
│       └── TagRepository.swift
├── Features/                       // 按功能垂直切分（见 04-screen-specs.md）
│   ├── Timeline/                   // TimelineHomeView + TimelineModel（定位/筛选双状态源）
│   ├── Editor/                     // MomentEditorView + Mood/Tag/Date/Time 弹层
│   ├── Preview/                    // MomentPreviewView + ImageViewerView
│   ├── Heatmap/ Filter/ Stats/     // 覆盖层 / 筛选 / 统计
│   ├── Settings/ Tags/ Trash/ Appearance/ About/   // 设置及子页
│   ├── Paywall/                    // ProPaywallView
│   └── Lock/                       // PrivacyLockView
├── DesignSystem/                   // 视觉与主题（见 05-design-system.md）
│   ├── ThemeManager.swift          // AppearancePreference 解析 + Environment 注入
│   ├── Colors.swift / Typography.swift
│   └── Components/                 // FAB、Chip、气泡卡片、进度条、弹选组件等
├── Services/
│   ├── Quota/                      // QuotaService
│   ├── Sync/                       // CloudKit 同步状态推导（见 09-icloud-sync.md）
│   ├── Auth/                       // LocalAuthentication 隐私锁（见 10-security-privacy.md）
│   └── Store/                      // StoreKit 2 订阅/买断（见 11-monetization.md）
├── Localization/
│   └── Localizable.xcstrings       // String Catalog：zh-Hans / en
└── Resources/
    └── Assets.xcassets             // 6 主色 Any/Dark 双值 Color Set、App 图标、插画
```

划分原则：
- **领域与持久化解耦**：`Models/` 存纯领域类型，`Persistence/` 存 `@Model` 与仓库；`Mood` 契约被两侧共同引用但只定义一次。
- **导航集中**：`Navigation/AppRouter.swift` 是唯一的跨页导航 source of truth，`Features/*` 只发意图、不各自持久化导航状态。
- **功能垂直切分**：每个 `Features/*` 对应导航映射表中一组 View，跨功能共享视觉组件下沉 `DesignSystem/Components`。
- **服务按外部依赖聚合**：`Services/Quota|Sync|Auth|Store` 隔离系统能力，接口 async、写入走 ModelActor。
- **本地偏好与订阅缓存**（`AppearancePreference` / `SubscriptionStateCache`）不落 SwiftData、不接 CloudKit，由 `UserDefaults`/`AppStorage` 承载，分归 `DesignSystem`（主题）与 `Services/Store`（订阅）。
