# 实现真相 · Implementation Truth

## Scope

本文只描述**已落地的运行时行为与结构**（阶段 0–5）。设计契约见 `../design/`，未实现工作见 `../plans/`。数值/枚举/色值以 `../design/` 为单一事实源，本文不复制。

## 模块结构（as-built）

代码在 `Sources/Moodments/`，按职责分区：

```text
App/            MoodmentsApp（装配 ModelContainer+AppRouter+ThemeManager）· RootView（浮层装配）· UITestSupport（DEBUG）
Navigation/     AppRouter（@MainActor @Observable 集中路由）
Models/         Mood(+DisplayName) · Quota · FilterCondition   （值类型/契约常量）
Persistence/    Moment · Tag · MomentImage · ModelContainer+Config
Persistence/Repositories/   MomentRepository · TagRepository · RepositoryError   （@ModelActor 后台写入）
Services/Quota/ QuotaService（唯一限额判定）
Services/Tag/   DefaultTagSeeder（首启预置，经 TagRepository）
Services/Media/ ImageCompressor（纯函数）· ThumbnailCache（actor，阶段 4 接线：同步/异步两个 thumbnail 重载）
DesignSystem/   Colors · Typography · ThemeManager · Components/*（含阶段 4 新增 ThumbnailStripView）
Features/       Timeline/*（阶段5：TimelineModel 上提，List 本体下沉 TimelineListView，新增 TimelineQuery/TimelineContextMarkerBar）· Editor/*（已落地）· Preview/*（阶段 4 落地：MomentPreviewView/ImageViewerView）· Trash/*（阶段 4 新增 TrashView）· Heatmap/*（阶段5落地：YearHeatmapView+YearHeatmapModel）· Filter/*（阶段5落地：FilterPanelView）· Stats/*（阶段5新增：MoodStatsView+MoodStatsModel）· Settings（已加心情统计/垃圾箱两入口）· Paywall（占位 stub，阶段7）
```

**分层与并发边界**：UI / `AppRouter` / `ThemeManager` / `MomentEditorModel` / `TimelineModel` / `YearHeatmapModel` / `MoodStatsModel`（阶段5新增）均 `@MainActor`；数据写入走 `@ModelActor` 仓库（后台）；跨隔离域只传值类型（`UUID` / `Data` / `Mood` / `MomentSnapshot` / `TagSnapshot` / `DraftPhoto` / `MomentImageData` / `[Int: Mood]` / `[Mood: Int]`），**不传 `@Model` 引用**。`ThumbnailCache` 为 `actor`。

## 数据模型（as-built）

实体 `Moment` / `Tag` / `MomentImage`（SwiftData `@Model`），字段与契约见 `../design/06-domain-model.md`、`../design/07-data-persistence.md`。仓库方法为 canonical，见 `Persistence/Repositories/`。

- `MomentRepository`（`@ModelActor`）：`createMoment` · `updateMoment`（含图片按序重建）· `editingPayload`（.edit 载入）· `fetchPage` · `totalMomentCount`（**含垃圾箱**）· `imageCount` · **删除生命周期 `softDelete` / `restore` / `purge` / `fetchTrash`**（阶段 1 即已实现并单测；阶段 4 接 UI）· **阶段 4 新增取图** `imageData(imageID:)`（单张原图，未命中缩略图时现场取）/ `orderedImageData(momentID:)`（一个 Moment 的全部原图，按 `sortIndex` 有序，供 `ImageViewerView` 一次性取全量）· **阶段5新增年度聚合**（`MomentRepository+Aggregation.swift`）`moodByDay(year:filter:)`（按年份区间取未软删除记录，正序遍历按天覆盖写入，得「当天最后一条」的心情，`filter` 非 `nil` 时先用 `FilterCondition.matches` 内存过滤再入桶；回传 `[Int: Mood]`，key 为 `Calendar.ordinality(of:.day, in:.year, for:)`）/ `moodCounts(year:)`（年度按情绪计数，恒全量、不接 `filter`，供 `MoodStatsView` 用）。
- `TagRepository`（`@ModelActor`）：`findTag(named:)`（应用层查重）· `createTag` · `deleteTag`（`.nullify` 关联）· `fetchAll` · `totalTagCount`。
- `fetchTrash` 排序口径（阶段 4 修正）：按 `deletedAt`（移入垃圾箱时间）倒序，区别于 `fetchPage`/额度计数用的 `occurredAt`（见 04-screen-specs.md §4.14）；`Moment.deletedAt` 字段自阶段 1 起已存在，本阶段只改排序键，未新增字段。

### 实现选择与 as-built 说明（本层为准；设计已覆盖的只引用不复述）

1. **软删除存储字段 `deletedFlag`（`isDeleted` 计算属性转发）**：此为数据模型 schema 契约，canonical 说明与「`#Predicate` 一律引用 `deletedFlag`」的规则在 `../design/07-data-persistence.md` §Moment 与 `Persistence/Moment.swift` 头注；实现与该契约一致（如 `@Query { $0.deletedFlag == false }`、`fetchTrash { $0.deletedFlag == true }`）。此处仅登记：实现遵循 07，不另立说法。
2. **标识用 `UUID`（非 `Moment.ID`）跨隔离域传递**（as-built 约定）。
3. **标题两态折叠机制（设计未指定 API，此处为 canonical）**：iOS 18+ 用系统 `onScrollGeometryChange` 读 `contentOffset`；iOS 17 回退 `PreferenceKey` 偏移探针 + `onPreferenceChange`（`TitleCollapseObserver`）。原因：本运行时（iOS 26）下 `ScrollView` 内 `.background(GeometryReader)` 的 preference 滚动期间不重算，命名/`.global` 坐标空间恒返回 0。见 `Features/Timeline/TimelineHomeView.swift`。
4. **UI 测试注入 hook（仅 DEBUG，`UITestSupport`，此处为 canonical）**：`-uiTestReset`（隔离内存容器）· `-uiTestSeedMoments`（15 条）· `-uiTestSeedMomentQuota`（10 条占满篇数额度）· `-uiTestPhotoInjection`（合成 JPEG 注入草稿，规避系统 `PhotosPicker` 不可被 XCUITest 驱动）。
5. **时间轴左滑删除容器迁移为 `List`（阶段 4，此处为 canonical）**：`TimelineHomeView` 由 `ScrollView { LazyVStack }` 迁移为 `List`，`.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + 逐行 `.listRowSeparator(.hidden)`/`.listRowBackground(.clear)`/`.listRowInsets(...)`/`.listRowSpacing(0)` 还原原有气泡视觉；真实 Moment 行的删除动作用系统 `.swipeActions`（`TimelineRowView.SwipeToDeleteModifier`），引导 Moment 行不挂该修饰符（不可删）。标题两态折叠机制不变（`TitleCollapseObserver` 对 `List` 与 `ScrollView` 同样适用，仅探针挂载点从「整个 LazyVStack 的 background」改为「首行（展开态大标题）的 background」，语义等价）。
6. **时间轴竖线连续性修正（阶段 4，修正一处此前即存在的缺陷，此处为 canonical）**：迁移前 `TimelineRowView` 用「行内竖线（在 24pt 列内居中）+ 独立延伸竖线（未居中，直接贴列起点）」两段拼接画法，两段的水平居中方式不一致，导致每行边界处竖线水平错位——`List` 引入的行间距使该错位从「觉察不到的直角拐点」变成「肉眼可见的断裂」，经真机截图比对定位。修正为**一条贯穿整行（卡片高度 + 行间延伸段）的单一背景竖线**（固定水平偏移 `64 + 12 + 12 = 88pt`，与心情节点圆点中心对齐），彻底消除错位，形成物理上连续的一条线，符合 `product-mental-model.md`「时间轴是连续对象，Moment/日期/心情节点挂载其上」的对象设计。
7. **预览/图片查看器的浮层归属（阶段 4，此处为 canonical）**：`MomentPreviewView` 由 `router.rootSheet` 的 `.preview(UUID)` 驱动（任务卡片栈第一层）；其内部「编辑」入口与图片查看器均为**预览自身局部持有**的第二层浮层（`.sheet(item:)` / `.fullScreenCover(item:)`），不写回 `router.rootSheet`/`router.fullScreenCover`——避免 sheet 之上从根 present 冲突。`RootView` 的 `router.fullScreenCover` → `ImageViewerView` 路径同步保留、指向同一 `ImageViewerView(momentID:startIndex:)`，供后续（如编辑器缩略图入口）复用同一呈现机制。
8. **缩略图缓存失效两处接线（阶段 4，解决阶段 3 遗留的孤儿缓存问题，此处为 canonical）**：① 彻底删除（`TrashView.handlePurge`）对 `MomentSnapshot.imageIDs` 逐个 `ThumbnailCache.removeThumbnail`；② 编辑保存（`MomentEditorModel.save` 的 `.edit` 分支）对 `load()` 时记录的 `originalImageIDs` 逐个失效——因 `updateMoment(imageDatas:)` 级联删除旧 `MomentImage` 并重建全新 id，旧键保存后必然是孤儿键。`ThumbnailCache` 新增 `async` 重载 `thumbnail(for:maxDimension:provideOriginal:)`（命中即返回、未命中才 `await` 拉原图，供跨 `@ModelActor` 仓库取图场景使用）与仅供测试的只读查询 `hasMemoryCachedThumbnail(for:)`。
9. **`TimelineModel` 上提到 `RootView`（阶段5必要重构，此处为 canonical）**：`TimelineHomeView` 不再自建 `@State private var timelineModel = TimelineModel()`，改由 `RootView` 持有并通过 `.environment()` 注入整棵树（含 `TimelineHomeView` 与热力图覆盖层 `YearHeatmapView`），二者共享同一实例，使热力图点格写入的 `heatmapFocusDate` 能被时间轴看到、热力图聚合读取的 `activeFilter` 与时间轴筛选是同一份状态。两个存储属性（`heatmapFocusDate` / `activeFilter`）保持分离，只新增派生只读 `isLocated` / `hasFilter`。
10. **定位≠筛选的结构化落实（阶段5，此处为 canonical，见 `docs/product-mental-model.md` 公理2）**：`TimelineQuery.predicate(for filter:) -> Predicate<Moment>` 签名内没有任何 `Date` 参数——类型层面杜绝定位污染数据集；`TimelineQuery.scrollTargetID(for date:, in entries:) -> UUID?` 是纯函数，只从调用方已经筛选好的 `entries` 里选一个 id，不修改/不返回数据集本身。`TimelineListView` 内两条链路彼此独立、互不引用：`@Query`（用 `init(filter:)` 动态构造，随 `activeFilter` 变化重新取数）与 `.onChange(of: heatmapFocusDate)`（只触发一次 `ScrollViewReader.scrollTo`）。标签 AND 交集（`#Predicate` 表达不了多值集合包含判断）改在内存用 `FilterCondition.matches(tagIDs:mood:)` 判定，同一份判定逻辑也被 `MomentRepository.moodByDay(year:filter:)` 复用，避免两处各自实现产生漂移。`LocateVsFilterTests`/`MultiTagFilterTests` 锁定该结构。
11. **热力图/统计聚合的并发边界（阶段5，此处为 canonical）**：`MomentRepository+Aggregation.swift` 的 `moodByDay`/`moodCounts` 运行在 `MomentRepository` 所在的后台 `ModelActor`；`YearHeatmapModel`/`MoodStatsModel`（均 `@MainActor @Observable`）用 `.task(id:)`（复合 key，年份 + 筛选条件）触发 `await` 调用，回传值类型 `[Int: Mood]`/`[Mood: Int]`，不传 `@Model` 引用。
12. **热力图覆盖层呈现形态改为顶部锚定非模态展开（阶段5，此处为 canonical，替换阶段2占位的全屏黑遮罩）**：`RootView` 用 `.overlay(alignment: .top)` + `.move(edge: .top).combined(with: .opacity)` 转场呈现 `YearHeatmapView`；覆盖层自身内容（非全屏尺寸）继承 `theme.canvasBackground` 作为卡片背景，背景时间轴保持可见、不下沉、不变暗——区别于任务卡片栈的模态下沉语义（依公理4）。
13. **容器级 `.accessibilityIdentifier` 覆盖子元素自身 identifier 的真实缺陷（阶段5 review 中定位并修复，此处为 canonical 教训登记）**：在 `FilterPanelView` 上同时给外层容器与内部各行 `Button` 设置 `.accessibilityIdentifier` 时，实测（`xcodebuild test` + `app.debugDescription` 打印无障碍树）外层容器的 identifier 会覆盖全部子行 `Button` 自己的 identifier（子行 label 正确、但 identifier 全部变成外层的值），导致 `XCUITest` 按子行 identifier 查找必然失败。修复：**不在包裹多个已自带 identifier 的交互子元素的容器上叠加容器级 `.accessibilityIdentifier`**，已在 `FilterPanelView`/`TimelineContextMarkerBar`/`YearHeatmapView`/`MoodStatsView` 的卡片容器上移除同类用法并加注释登记；此为通用 SwiftUI 无障碍树注意事项，非本 App 特例，供后续新增容器级 identifier 前先复核。

## 导航与浮层（as-built）

- **集中路由** `AppRouter`：`rootSheet: RootSheet?`（`.preview(UUID)` / `.editor(EditorMode)` / `.settings` / `.paywall(PaywallTrigger)`）· `fullScreenCover: FullCover?`（`.imageViewer(momentID:index:)`，阶段 4 起指向真实 `ImageViewerView`）· `isHeatmapPresented` · `homePath` · `isLocked`。
- **`RootView` 装配**：`.sheet(item: $router.rootSheet)`（任务卡片栈第一层）· `.fullScreenCover(item:)`（沉浸全屏）· 热力图 `.overlay(alignment: .top)`（阶段5改为顶部锚定非模态展开，`.move(edge: .top).combined(with: .opacity)` 转场，继承 `theme.canvasBackground`，见上方「实现选择」条目 12；阶段2的全屏黑遮罩占位已替换）。
- **就近浮窗不进 Router**：情绪/标签/日期/时间选择、筛选面板用 `.popover + presentationCompactAdaptation(.popover)`，由触发处**局部 `@State`** 驱动。`FilterPanelView`（阶段5落地真实内容）由 `TimelineHomeView` 局部 `@State private var isFilterPresented` 驱动，绑定 `timelineModel.activeFilter`（经 `@Bindable`），不进 Router。
- **第二层浮层由 sheet 内容自身局部状态驱动**：编辑器内「新建标签」/「照片额度 Paywall」用编辑器局部 `.sheet(item:)`；预览内「编辑」/「图片查看器」用预览局部 `.sheet(item:)`/`.fullScreenCover(item:)`（阶段 4）——均不塞进 `rootSheet`/`fullScreenCover`（否则替换而非层叠）。
- **垃圾箱 + 心情统计**（阶段 4 / 阶段5）：`SettingsSheetView` 的 `NavigationStack` 内两个 `NavigationLink` push `TrashView`（`accessibilityIdentifier: settingsTrashRow`）/ `MoodStatsView`（`accessibilityIdentifier: settingsMoodStatsRow`，阶段5新增），符合 08 §2.2「设置栈内子页」映射；`MoodStatsView` 独立全量、不接 `TimelineModel`（见 `MoodStatsModel` 头部注释）。

## 运行时流（as-built）

**启动 + 首启预置**
```text
MoodmentsApp.init → 选容器（DEBUG 且 -uiTest* → 内存；否则本地）
RootView.task → DefaultTagSeeder.seedIfNeeded(TagRepository)（Tag 表空才预置）
             → (DEBUG) UITestSupport 按 launch args seed
```

**记录 → 保存 → 上屏**
```text
TimelineHomeView FAB → handleNewMomentTapped:
  MomentRepository.totalMomentCount + QuotaService.checkCanCreateMoment
    allowed  → router.rootSheet = .editor(.create)
    exceeded → router.rootSheet = .paywall(.quotaMoment)   （编辑器不打开）
MomentEditorView(MomentEditorModel 草稿, 值类型) → 就近浮窗选情绪/标签/日期/时间 + 照片(压缩)
  保存 → MomentEditorModel.save → repository.createMoment/updateMoment（后台 ModelActor）
       → dismiss → 时间轴 @Query 自动按 occurredAt 倒序反映（补记落到过去位置）
```

**额度闸门（三处，判定只走 `QuotaService`，数值只来自 `Quota`）**
```text
篇数：TimelineHomeView 点新建时判定 → 超额 Paywall（第一层，编辑器不开）
照片：EditorPhotoSection 追加时 model.checkCanAddPhoto → 超额 编辑器局部 Paywall（第二层）
标签：TagPickerView「+添加」时 model.requestCreateTag → 超额 编辑器局部 Paywall（第二层）
```
Pro 感知：`QuotaService` 对 Pro 短路 `.allowed`；剩余额度经 `remainingPhotoSlots`（Pro 返回 `.max`）派生，View 不自算。

**删除生命周期（阶段 4 接线）**
```text
时间轴左滑（List.swipeActions/accessibilityAction）→ TimelineHomeView.handleDelete
  → MomentRepository.softDelete（后台 ModelActor）→ @Query 自动移除该行（不释放额度、缩略图不动）
设置「垃圾箱」→ TrashView.task → MomentRepository.fetchTrash（按 deletedAt 倒序）
  leading swipe「恢复」→ restore → reload（回到时间轴原 occurredAt 位置）
  trailing swipe「彻底删除」→ .alert 二次确认 → purge（释放额度）+ 逐个 ThumbnailCache.removeThumbnail(imageIDs) → reload
```

**缩略图现状（阶段 4 接线）**：草稿照片仍由 `jpegData` 现场解码显示（量小，未走缓存）；持久化后的缩略图经 `ThumbnailStripView`（时间轴气泡 + 预览照片区共用）按需调用 `ThumbnailCache.thumbnail(for:provideOriginal:)`——命中缓存直接展示，未命中才 `await MomentRepository.imageData(imageID:)` 现场取原图生成；`ImageViewerView` 打开时一次性经 `orderedImageData(momentID:)` 取全量原图（不走缩略图缓存，用户已明确要看大图）。失效两处见上方「实现选择」条目 8。

**回看：定位/筛选/聚合（阶段5接线）**
```text
筛选：TimelineHomeView 收起态「时刻⌄」→ FilterPanelView（popover，绑定 timelineModel.activeFilter）
  点标签/心情行 → 即时写 activeFilter → TimelineHomeView 重新构造 TimelineListView(filter:)
    → @Query 用 TimelineQuery.predicate(for:) 重新取数（谓词只含 deletedFlag+mood）
    → 标签 AND 交集在内存用 FilterCondition.matches 过滤 → entries 变化 → List 重渲染

定位：TimelineHomeView 顶部日历图标 → router.isHeatmapPresented = true
  → RootView.overlay(alignment: .top) 展开 YearHeatmapView（继承 TimelineModel 环境）
  → YearHeatmapModel.task(id: year+filter) → repository.moodByDay(year:filter:)（后台 ModelActor）
  → HeatmapGridView 渲染日期格；点「有记录」格 → handleSelectDay
    → 同格重复点击 → timelineModel.heatmapFocusDate = nil（取消定位）
    → 否则 → timelineModel.heatmapFocusDate = 当天 23:59:59（合成锚点）
  → TimelineListView.onChange(of: heatmapFocusDate) → TimelineQuery.scrollTargetID(for:in:)
    在当前 entries（已按 filter 筛选好的可见集）里挑锚点 id → ScrollViewReader.scrollTo（不重建 @Query）
  → 命中行按 highlightedID 叠加 theme.accent.opacity(0.14) 高亮（TimelineListView 计算属性，纯派生）

上下文标记：TimelineHomeView topBarStack 内 TimelineContextMarkerBar（hasFilter || isLocated 时显示）
  → 各自 X：移除某个 tagID / 清 mood / 清 heatmapFocusDate，互不覆盖对方

心情统计：SettingsSheetView → NavigationLink push MoodStatsView
  → MoodStatsModel.task(id: year) → repository.moodByDay(year:filter: nil) + repository.moodCounts(year:)
  → 卡片1 HeatmapGridView（不可交互、不接 selectedDate）+ 卡片2 8×MoodStatBarView（emoji+名称+N次+占比条）
```

## 验证基线

见 `README.md` §验证基线（统一入口 `./scripts/verify.sh`；阶段5收口：单元 63 + UI 7 套件/13 用例全过、build ✓、lint ✓）。
