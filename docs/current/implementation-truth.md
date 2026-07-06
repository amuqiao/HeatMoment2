# 实现真相 · Implementation Truth

## Scope

本文只描述**已落地的运行时行为与结构**（阶段 0–3）。设计契约见 `../design/`，未实现工作见 `../plans/`。数值/枚举/色值以 `../design/` 为单一事实源，本文不复制。

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
Services/Media/ ImageCompressor（纯函数）· ThumbnailCache（actor，已交付未接线）
DesignSystem/   Colors · Typography · ThemeManager · Components/*
Features/       Timeline/*（已落地）· Editor/*（已落地）· Preview/Heatmap/Filter/Settings/Paywall（占位 stub）
```

**分层与并发边界**：UI / `AppRouter` / `ThemeManager` / `MomentEditorModel` / `TimelineModel` 均 `@MainActor`；数据写入走 `@ModelActor` 仓库（后台）；跨隔离域只传值类型（`UUID` / `Data` / `Mood` / `MomentSnapshot` / `TagSnapshot` / `DraftPhoto`），**不传 `@Model` 引用**。`ThumbnailCache` 为 `actor`。

## 数据模型（as-built）

实体 `Moment` / `Tag` / `MomentImage`（SwiftData `@Model`），字段与契约见 `../design/06-domain-model.md`、`../design/07-data-persistence.md`。仓库方法为 canonical，见 `Persistence/Repositories/`。

- `MomentRepository`（`@ModelActor`）：`createMoment` · `updateMoment`（含图片按序重建）· `editingPayload`（.edit 载入）· `fetchPage` · `totalMomentCount`（**含垃圾箱**）· `imageCount` · **删除生命周期 `softDelete` / `restore` / `purge` / `fetchTrash`**（阶段 1 即已实现并单测；阶段 4 接 UI）。
- `TagRepository`（`@ModelActor`）：`findTag(named:)`（应用层查重）· `createTag` · `deleteTag`（`.nullify` 关联）· `fetchAll` · `totalTagCount`。

### 实现选择与 as-built 说明（本层为准；设计已覆盖的只引用不复述）

1. **软删除存储字段 `deletedFlag`（`isDeleted` 计算属性转发）**：此为数据模型 schema 契约，canonical 说明与「`#Predicate` 一律引用 `deletedFlag`」的规则在 `../design/07-data-persistence.md` §Moment 与 `Persistence/Moment.swift` 头注；实现与该契约一致（如 `@Query { $0.deletedFlag == false }`、`fetchTrash { $0.deletedFlag == true }`）。此处仅登记：实现遵循 07，不另立说法。
2. **标识用 `UUID`（非 `Moment.ID`）跨隔离域传递**（as-built 约定）。
3. **标题两态折叠机制（设计未指定 API，此处为 canonical）**：iOS 18+ 用系统 `onScrollGeometryChange` 读 `contentOffset`；iOS 17 回退 `PreferenceKey` 偏移探针 + `onPreferenceChange`（`TitleCollapseObserver`）。原因：本运行时（iOS 26）下 `ScrollView` 内 `.background(GeometryReader)` 的 preference 滚动期间不重算，命名/`.global` 坐标空间恒返回 0。见 `Features/Timeline/TimelineHomeView.swift`。
4. **UI 测试注入 hook（仅 DEBUG，`UITestSupport`，此处为 canonical）**：`-uiTestReset`（隔离内存容器）· `-uiTestSeedMoments`（15 条）· `-uiTestSeedMomentQuota`（10 条占满篇数额度）· `-uiTestPhotoInjection`（合成 JPEG 注入草稿，规避系统 `PhotosPicker` 不可被 XCUITest 驱动）。

## 导航与浮层（as-built）

- **集中路由** `AppRouter`：`rootSheet: RootSheet?`（`.preview(UUID)` / `.editor(EditorMode)` / `.settings` / `.paywall(PaywallTrigger)`）· `fullScreenCover: FullCover?`（`.imageViewer`）· `isHeatmapPresented` · `homePath` · `isLocked`。
- **`RootView` 装配**：`.sheet(item: $router.rootSheet)`（任务卡片栈第一层）· `.fullScreenCover(item:)`（沉浸全屏）· 热力图 `.overlay`。
- **就近浮窗不进 Router**：情绪/标签/日期/时间选择、筛选面板用 `.popover + presentationCompactAdaptation(.popover)`，由触发处**局部 `@State`** 驱动。
- **第二层浮层由 sheet 内容自身局部状态驱动**：编辑器内「新建标签」/「照片额度 Paywall」用编辑器局部 `.sheet(item:)`，不塞进 `rootSheet`（否则替换而非层叠）。

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

**缩略图现状**：草稿照片直接由 `jpegData` 解码显示（量小）；`ThumbnailCache`（持久化后缩略图）**尚未接线**，阶段 4 接入。

## 验证基线

见 `README.md` §验证基线（统一入口 `./scripts/verify.sh`；阶段 3 收口：单元 38 + UI 6 套件全过、build ✓、lint ✓）。
