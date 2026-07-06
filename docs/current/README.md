# 时刻 / Moodments —— 实现真相层（current）

本目录记录**现在实际实现了什么**（as-built）：已发布能力、模块边界、运行时行为、对设计的偏离、验证基线。与另外三层的分工：

| 层 | 位置 | 回答 | 时态 |
|---|---|---|---|
| 公理层 | `../product-mental-model.md` | 产品是什么（不可违背规则） | — |
| 契约/设计层 | `../design/` | **应该**怎么做（前瞻规格、下游稳定契约） | 将来式/规范式 |
| **实现真相层（本目录）** | `current/` | **现在实际**怎么实现的（含偏离设计之处） | **现在式，仅已落地** |
| 计划层 | `../plans/implementation-plan.md` | 还没做什么（缺口 + 验收标准） | 将来式 |

> **写作规则**：本层只写已落地行为（现在式）；限额/色值/枚举等**设计事实不在此复制**，引用 `../design/` 单一事实源；本层只记「as-built 结构、运行时路径、对设计的偏离、验证基线」。计划态不写进本层（在 `plans`），完成后其真相落入本层、并在 plan 标 ✅ 只留验收证据。

## 文档地图

| 文件 | 内容 |
|---|---|
| `README.md`（本文） | 能力/状态矩阵 · 验证基线 · 维护规则 |
| `implementation-truth.md` | as-built 架构与模块边界 · 数据模型落地与偏离 · 运行时流 · 导航/浮层落地 |

## 能力 / 状态矩阵（按实现阶段）

| 阶段 | 状态 | 已落地要点 |
|---|---|---|
| 0 脚手架 / scripts | ✅ | XcodeGen（`Project.yml`）· `scripts/`（bootstrap/gen/build/test/lint/run/verify/clean）· CI 与本地同入口 `verify.sh` |
| 1 领域与数据契约 | ✅ | `Mood`(8) · `Quota` · SwiftData 实体 `Moment`/`Tag`/`MomentImage` · 仓库 `MomentRepository`/`TagRepository`（含**完整删除生命周期方法** softDelete/restore/purge/fetchTrash）· `QuotaService` · `AppRouter` |
| 2 时间轴首屏 + 设计系统 + 导航骨架 | ✅ | `TimelineHomeView`（气泡时间轴、每情绪心情色、标题两态折叠、FAB、空态 3 引导）· 设计系统（Colors/Typography/ThemeManager/组件）· `RootView` 浮层装配 · 各 Feature 占位 stub |
| 3 记录 / 编辑 | ✅ | `MomentEditorView`+`MomentEditorModel` · 四就近浮窗（情绪/标签/日期/时间）· 新建标签第二层 sheet · 图片压缩管线 · 篇/图/标签额度闸门 · 首启默认标签预置 · 编辑态照片增删 |
| 4 预览 + 删除生命周期 | ✅ | `MomentPreviewView`（弹出阅读卡片，ADR-007）· 预览内编辑/图片查看器为局部第二层浮层 · `ImageViewerView`（`.fullScreenCover`，捏合/双击缩放）· `TrashView`（设置栈内 push，恢复/彻底删除 + 二次确认）· 时间轴左滑删除迁移为 `List`+`.swipeActions`（标题两态折叠保留）· 缩略图缓存接线（`ThumbnailStripView`）+ 编辑保存/彻底删除两处失效 |
| 5 回看（热力图 + 统计） | ✅ | `YearHeatmapView`（顶部锚定非模态展开、年份 2021–2026、日期格=当天最后一条心情色、点格定位/再点取消）· `MoodStatsView`（心情日期分布 + 8 情绪条形，全量不接筛选）· `FilterPanelView`（标签多选 AND + 心情单选，即时生效）· 定位≠筛选双状态源接通（`TimelineModel` 上提到 `RootView`）· 上下文标记横条（筛选/时间标记并存、各自可移除） |
| 6 设置 + 外观主题 | ✅ | `SettingsSheetView` 完整分组（Pro 横幅/心情统计/标签管理/垃圾箱/iCloud·面容·语言占位/外观主题/关于/版本页脚）· `TagManageView`（新建/重命名/删除，删除同步清理筛选陈旧 id）· `AppearanceThemeView`（模式/主色/网格/图片即时生效 + 三类异常页内提示）· `AboutView`（强制亮色+固定红）· `AppearanceStore`（逐轴持久化）· 统一错误通道 `ErrorPresenter`/`.userFacingErrorAlert` |
| 7 支撑能力（iCloud/面容/语言/订阅） | ⬜ | 见 `plans`（`ProPaywallView` 为占位；`QuotaService` 用默认非 Pro provider） |

## 功能能力现状（跨阶段视角）

| 能力 | 现状 | 说明 |
|---|---|---|
| 浏览时间轴 | ✅ | `@Query { deletedFlag == false }` 按 `occurredAt` 倒序 |
| 记录 / 编辑 Moment | ✅ | 情绪/标题/正文/标签/发生时间(可补记)/照片 |
| 就近浮窗 | ✅ | popover + `presentationCompactAdaptation(.popover)`，不进 `AppRouter` |
| 图片添加 + 压缩 | ✅ | HEIC→JPEG，长边≈2048/质量≈0.8/<500KB(best-effort) |
| 额度闸门 + Paywall 占位 | ✅ | 篇（点新建）/图/标签三处；判定只走 `QuotaService` |
| 默认标签预置 | ✅ | 首启经后台 `TagRepository` 预置 工作/生活/健康 |
| 预览阅读卡片 | ✅ | `MomentPreviewView`：心情/日期/编辑入口/标题/标签/照片/正文；`@Query` 按 id 取活对象，编辑保存后自动反映 |
| 图片查看器 | ✅ | `ImageViewerView`（`.fullScreenCover`）：`TabView(.page)` 分页 + 捏合/双击缩放；预览局部呈现，`RootView` 的 `router.fullScreenCover` 路径同步接入供后续复用 |
| 删除生命周期（UI） | ✅ | 时间轴 `List`+`.swipeActions` 左滑软删除（无二次确认）· `TrashView` 恢复（leading swipe）/彻底删除（trailing swipe + `.alert` 二次确认）· `fetchTrash` 按 `deletedAt` 倒序 |
| 缩略图缓存 | ✅ | `ThumbnailStripView` 经 `ThumbnailCache` 异步重载按需加载；彻底删除失效 `imageIDs`、编辑保存失效 `originalImageIDs` 两处接线 |
| 热力图 / 统计 / 筛选 | ✅ | `YearHeatmapView`/`FilterPanelView`/`MoodStatsView` 已落地真实内容，见上方阶段 5 行 |
| 设置 / 外观主题 | ✅ | 见上方阶段 6 行 |
| iCloud / 面容 / 语言 / 订阅 | ⬜ | 阶段 7；CloudKit config 已注释预留；设置页对应三行现为禁用占位（「即将推出」） |

## 验证基线

- **统一入口**：`./scripts/verify.sh` = lint（swiftlint + swift-format）→ build → test。CI 与本地同一入口。
- **分项**：`./scripts/build.sh` · `./scripts/test.sh [--unit|--ui|--all]` · `./scripts/lint.sh [--fix]` · `./scripts/gen.sh`（改 `Project.yml` 或增删源文件后重生成工程）· `./scripts/run.sh`。
- **模拟器**：iPhone 17 / iOS 26.5（部署目标 iOS 17）。
- **当前基线（阶段 6 收口）**：`** BUILD SUCCEEDED **` · 单元 **87** 全过（22 套件）· UI **25 用例 / 11 套件**全过 · lint 干净（无新增 swiftlint 违规，仅既有测试文件的 `LineLength` 风格提示）。

单元测试套件（`Tests/MoodmentsTests/`）：`MoodTests` · `QuotaServiceTests` · `MomentLifecycleTests` · `MomentDiskRoundTripTests` · `MomentRepositoryTests` · `MomentRepositoryEditingTests` · `TagRepositoryTests`（阶段6补 renameTag 4 例）· `MomentOccurredAtOrderingTests` · `EditorSaveValidationTests` · `ImageCompressorTests` · `DefaultTagSeederTests` · `MomentQuotaReleaseTests` · `MomentRestoreOrderingTests` · `MomentImageFetchTests` · `ThumbnailCacheInvalidationTests` · `LocateVsFilterTests`（阶段5新增）· `MultiTagFilterTests`（阶段5新增）· `HeatmapMoodColorTests`（阶段5新增）· `MoodColorPaletteTests`（阶段6新增）· `AppearanceStoreTests`（阶段6新增）· `ErrorPresenterTests`（阶段6新增）· `TimelineModelTests`（阶段6新增）。

UI 测试套件（`Tests/MoodmentsUITests/`）：`AppLaunchUITests` · `TimelineEmptyStateUITests` · `TitleCollapseFilterUITests` · `EditorSheetPresentationUITests` · `CreateMomentFlowUITests` · `QuotaBlockUITests` · `DeleteRestorePurgeUITests` · `LocateFilterUITests`（阶段5新增）· `ThemeSwitchUITests`（阶段6新增）· `AppearanceSaveFailureUITests`（阶段6新增）· `TagManageUITests`（阶段6新增）。

## 维护规则

- 每个实现阶段**验收通过后**：把该阶段的 as-built 真相并入本层（`implementation-truth.md` + 上表状态），plan 层对应阶段标 ✅ 只留验收证据。
- **对设计的偏离**记录在本层（`implementation-truth.md` §偏离），不写进 `design/` 契约层；契约层若需相应调整，另行回改并注明。
- 本层不复制设计数值，引用 `design/` 保持单一事实源。
