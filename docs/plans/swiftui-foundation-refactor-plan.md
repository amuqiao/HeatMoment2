# SwiftUI 小而美应用骨架重构计划

本文是一份主动计划：目标是把 HeatMoment 收口成可作为后续 SwiftUI 小应用参考的基础骨架，同时不把单机日记 App 膨胀成通用框架。已实现事实以 [`../current/`](../current/README.md) 为准；产品语义以 [`../product-mental-model.md`](../product-mental-model.md) 为准；本地数据生命周期、iCloud 与 asset GC 仍归 [`implementation-plan.md`](implementation-plan.md) 管理。

## Planning Position

用户真实诉求：

- HeatMoment 仍是一个小而美的 Moment 记录 App，不做账号系统、不做自建后端、不做过度平台化。
- 这个项目也要成为以后 SwiftUI 小应用的示范骨架：日记、打卡、番茄日记等项目可以复用基础能力，再替换业务 feature。
- 复用的是稳定能力和组合方式，不是强行复用 HeatMoment 的首页、时间轴、心情、标签、热力图业务形状。
- 架构要借鉴成熟模板项目的“稳定合同 + 单向依赖 + 能力注册/装配”思想，但遵循 SwiftUI 原生范式，不照搬 FastAPI 分层命名。
- 本项目尚未上线；M-foundation 每个阶段只保留一条真实运行路径，不保留双路由、双服务、双数据源或无写入方的预留入口。

这里说的“模板效果”是稳定静态接入骨架，不是运行时插件系统：

```text
新增业务或新小 App
  -> 定义业务对象和产品公理
  -> 新增或替换 Business Feature
  -> 在 App Composition 显式接线 root scene / sheet / settings entry
  -> 复用 Foundation Capability
  -> 补 feature flow / capability / UI smoke 测试
```

SwiftUI 侧的成熟模式是显式组合和清晰依赖边界，而不是把后端 `job_type registry` 思路照搬成动态 feature registry。

目标心智模型：

```text
App Composition
  -> Business Features
      -> Foundation Capability Contracts
          -> Capability Internals
              -> Persistence / Apple Frameworks / File System
```

依赖规则：

- `App Composition` 负责启动、全局路由、scene lifecycle、根级 sheet/full screen policy 和依赖装配。
- `Business Features` 负责 HeatMoment 业务：Timeline、Editor、Preview、Heatmap、Filter、Tags、Trash、Stats、Settings、Paywall 等。
- `Foundation Capability Contracts` 负责可复用能力合同：sheet 骨架、设置导航、隐私锁、外观、日期时间控件、数据读写用例、备份恢复、导出、订阅权益、测试 harness。
- `Capability Internals` 负责具体实现：GRDB/SQLite、FileAssetStore、StoreKit、LocalAuthentication、FileManager、CloudKit 后续实现。
- 业务 feature 不直接 new 基础设施 concrete service；基础能力不反向依赖业务 feature。
- `DesignSystem` 的基础容器不能读取 repository、service 或 HeatMoment 业务模型；业务语义组件要进入业务 feature 或业务 UI 层。

非目标：

- 本轮不把仓库改成多 App monorepo。
- 本轮默认不拆 Swift Package / 多 target；先用目录、合同和测试守住边界。只有当边界无法靠单 target 维护时，再评估独立 target。
- 本轮不实现 iCloud 同步、不扩展 Pro 商品、不重做本地数据模型；这些只在边界收口时调整归属。
- 不为了“模板感”引入 registry everywhere、复杂 DI 容器或自定义导航框架。
- 不引入动态插件、自动路由发现、通用页面 DSL、通用业务 DSL 或运行时 feature loading。
- 不把“未来可以复用”理解为复制 HeatMoment 的业务对象；`Moment`、`Mood`、`Tag`、`Timeline`、`Heatmap` 只能作为 HeatMoment 业务参考，不进入 Foundation 合同。
- 不做双骨架并存；职责接管后只保留单一路径。

## Current Fact Source

本计划不复制当前架构、sheet system、数据源或测试入口清单。已落地事实统一维护在
[`../current/`](../current/README.md)；继续执行或重新打开本计划前，先读取 current，
再只把尚未完成的 gap、planned work 和验收条件写回本文件。

## Remaining Gaps

- M-foundation 主线已进入收口态；关闭证据保留在各阶段条目中，as-built 事实维护在 current。
- 新发现的骨架问题如果仍属于 App composition、Foundation UI、Capability contract 或测试守卫，再作为新的 gap 写入本节。
- iCloud sync、asset GC 等数据生命周期后续项不写入本计划，继续由 [`implementation-plan.md`](implementation-plan.md) 管理。

## Planned Work

### M-foundation-0: 文档路由与合同归属校准

目标：先按 `current / contract / plans` 校准文档归属，再开始移动代码，避免把未来计划写成当前事实，也避免创建第二套影子文档。

工作项：

- 复核 `AGENTS.md`、`docs/current/`、`docs/plans/` 和代码注释中的文档地图，确认文档事实源只落在当前三层职责内。
- 按 `$implementation-contract-plans` 分类现有内容：
  - `current`：已经实现的架构、运行流、数据模型、能力路径、验证基线。
  - `contract`：业务 feature 或基础能力调用方可以依赖的稳定能力边界、输入输出、状态语义。
  - `plans`：尚未完成的 gap、planned work、acceptance。
- 将散落在计划、current 和代码注释里的内容按归属移动或改写：current 只保留 as-built 和已实现能力边界，plans 只保留未完成工作。
- 在 current 或 plan 的最近相关页面中写清 SwiftUI 应用骨架边界，固定 `App Composition -> Business Features -> Foundation Capability Boundaries -> Capability Internals` 的单向依赖；不扩展成通用 framework 设计。
- 建立现有目录到目标层的映射表，标明哪些目录保持、哪些文件需要迁移、哪些只是重命名或换归属。
- 明确“可复用基础能力”和“HeatMoment 业务能力”的判断准则：
  - 能被日记、打卡、番茄日记复用的是 foundation。
  - 含 Moment、Mood、Tag、Timeline、Heatmap 产品语义的是 HeatMoment business。
  - 含 GRDB、StoreKit、LocalAuthentication、FileManager 的是 capability internal / infrastructure。
- 记录是否拆 target 的决策：默认不拆；先以目录规则和边界测试治理。

验收：

- 文档地图明确说明 product、current、plans 的实际文件位置；不存在与地图冲突的引用。
- current 不承诺未来能力；plans 不伪装成已实现事实。
- 已实现能力边界能反向映射到当前 `Sources/HeatMoment` 目录，不出现空泛层名。

### M-foundation-1: 稳定 AppShell 与路由表达（已关闭）

目标：让根应用壳只负责全局装配和呈现规则，业务首页和业务 sheet 作为可替换组合件接入。

关闭证据：

- `RootView` 已拆成 root scene、presentation policy、app readiness 三个私有边界。
- `AppRouter` 已删除空 push 路由和无写入方全局 full-screen 路由；图片查看器只保留 `MomentPreviewView` 局部 `.fullScreenCover(item:)` 这一条真实路径。
- 验证通过：`./scripts/build.sh`；`./scripts/test.sh --only HeatMomentUITests/EditorSheetPresentationUITests --only HeatMomentUITests/DeleteRestorePurgeUITests/testPreviewIsCardNotPush --only HeatMomentUITests/DeleteRestorePurgeUITests/testPreviewEditButtonPresentsNestedEditor`。

工作项：

- 把 `RootView` 当前职责拆成可读边界：
  - app readiness / launch restore / default seed 属于 app composition。
  - root home content 属于 HeatMoment business feature。
  - root sheet/full screen presentation policy 属于 app shell。
- 保留 SwiftUI 原生 `.sheet(item:)`、`.fullScreenCover(isPresented:)`、局部 `.fullScreenCover(item:)` 和 `NavigationStack`；不引入自定义导航框架，也不保留未使用的全局路由预留字段。
- 将 `RootSheet` 的基础呈现规则与 HeatMoment 业务 case 分清职责。业务 case 可以继续存在，但 AppShell 文档和代码结构要表达“这里负责呈现策略”，而不是把业务页面接线散落到各处。
- 明确三类浮层合同：
  - 根级任务 sheet：预览、编辑、设置、权益说明。
  - 就地选择层：筛选、日期、时间、心情/标签字段选择。
  - 沉浸全屏：隐私锁、pending restore 由 App composition 挂载；图片查看器由发起 feature 就近挂载。
- 保持 HeatMoment 产品公理：“永不离开主场景”和“两种浮层层级”不被架构抽象破坏。

验收：

- HeatMoment 首页不需要承载隐私锁、主题、语言、StoreKit、恢复 pending overlay 等 App 级能力；这些能力由 App composition 统一治理。
- `RootView` 中业务 switch 的剩余部分有明确归属；不存在空 push path、无写入方 fullScreen path 或新旧并存路由。
- 现有预览、编辑、设置、Paywall、图片查看器、隐私锁、pending restore 行为不回归。

### M-foundation-2: 拆清 Foundation UI 与业务 UI（已关闭）

目标：让 sheet、容器、按钮、排版、设置列表等基础 UI 可复用；让 HeatMoment 的心情、热力图、气泡、时间轴语义留在业务层。

关闭证据：

- `DesignSystem` 只保留基础 sheet/container/theme/typography/appearance/swipe 能力；`Mood`、`Moment`、`Tag`、`Timeline`、`Heatmap` 业务 UI 已迁入对应 `Features/*`。
- `MoodPalette` 已从基础主题 token 拆出，归入 `Features/Mood`；`TimelineSceneStyle` 归入 `Features/Timeline`；照片轨道尺寸规则归入 `Features/MomentMedia`，旧 `MomentPhotoRailView` 已删除。
- 验证通过：`./scripts/build.sh`；`./scripts/test.sh --only HeatMomentTests/MoodPaletteTests --only HeatMomentTests/TimelineSceneMetricsTests --only HeatMomentTests/MomentCardLayoutTests`。
- 边界扫描通过：`DesignSystem` 中无 `Mood`、`Moment`、`Tag`、`Heatmap`、`Timeline`、`Canonical`、`Repository`、`Service`、`MoodPalette` 和旧主题门面引用。

工作项：

- 将 `DesignSystem/Containers` 作为 Foundation UI 的核心候选：`AppSheetScaffold`、`AppSheetNavigationChrome`、`TaskContainerStyle`、`TaskPageScrollView` 等优先保留。
- 审计 `DesignSystem/Components`：
  - 基础组件继续留在 foundation UI。
  - `Mood`、`Moment`、`Heatmap`、`Timeline`、`Tag` 语义组件迁到 HeatMoment 业务 UI 区域。
- 将心情色、Mood palette、heatmap palette 与基础主题 token 拆开；基础主题只保留 App surface、task surface、semantic intent、typography、spacing 等通用能力。
- 统一 sheet 顶部按钮和导航 chrome 的使用约束，避免编辑页、预览页、设置页反复出现两套按钮样式。
- 日期、时间、滚筒、popover 锚点先按编辑页现有行为收口合同；只有当控件不含 Moment 语义、且至少被两个业务场景稳定复用时，才沉淀为 Foundation UI 控件。`occurredAt` 仍是 Moment 发生时间唯一事实。

验收：

- Foundation UI 文件不直接读取 `CanonicalLibraryService`、repository 或 HeatMoment service。
- Foundation UI 中不出现 `Mood`、`Moment`、`Tag`、`Heatmap`、`Timeline` 等业务模型依赖；允许业务层用 foundation 容器组装这些语义。
- Moment 编辑页顶部呼吸间隔、sheet 按钮样式、设置详情页返回样式都由同一套 sheet/container 合同约束。

### M-foundation-3: 收口 Settings 信息架构与能力入口（已关闭）

目标：设置页只做入口编排和详情页导航，不再成为支撑能力实现的落脚点。

关闭证据：

- `SettingsSheetView` 已按“个人化 / 数据与安全 / 管理 / 权益与关于”分组；`数据与 iCloud` 是行内系统同步状态，不是账号或登录入口；`面容解锁` 是根页轻量开关或不可用状态。
- 设置详情入口已改为 `SettingsNavigationEntry -> SettingsRoute -> settingsDestination(for:)`，row 只声明标题、identifier 和目标 route，不再在每个 row 内 inline 拼 destination。
- 验证通过：`./scripts/build.sh`；`./scripts/test.sh --only HeatMomentUITests/EditorSheetPresentationUITests/testSettingsRootHasNoExplicitCloseAndChildPageKeepsBackButton --only HeatMomentUITests/EditorSheetPresentationUITests/testSettingsTaskSurfacesShareHorizontalBounds --only HeatMomentUITests/EditorSheetPresentationUITests/testSettingsPrimaryDetailPagesUseUnifiedNavigationTitles --only HeatMomentUITests/EditorSheetPresentationUITests/testSettingsSupportDetailPagesUseUnifiedNavigationTitles`。
- 未关闭项：`BackupRestoreServicing`、导出 snapshot 组装、隐私锁服务等跨 feature capability 合同仍归 M-foundation-4，不在 M3 假装完成。

工作项：

- 不把设置页产品 IA 重排作为本阶段的架构门槛；本阶段只固定入口归属和能力边界。已确认的推荐分组作为 UI 收口参考：
  - 个人化：外观、语言。
  - 数据与安全：数据与 iCloud、备份与恢复、导出、面容解锁。
  - 管理：标签、垃圾箱、统计。
  - 权益与关于：Pro、关于。
- 建立设置入口合同：每个 row 只声明标题、摘要、状态、目标详情页或 toggle action；能力实现留在对应 capability。
- 面容解锁根页开关保持轻量；只有需要解释、失败重试或系统能力状态时才进入详情页，避免无意义详情页。
- 备份恢复详情页只消费恢复点列表、恢复动作和状态；不拥有 recovery coordinator。
- 导出详情页只消费 `ExportRequest`、日期范围校验和导出动作；不直接组装 canonical snapshot store。
- iCloud 详情页后续只展示系统 Apple ID/iCloud 状态和同步状态，不表达成 App 登录或云端备份。

验收：

- 用户能清楚区分本地存储、自动恢复点、导出副本、iCloud 同步、面容解锁、Pro 权益。
- 设置根页没有“登录/账号”暗示；iCloud 明确是系统能力，不是 HeatMoment 账号。
- 设置根页不表达登录/账号，也不把支撑能力实现写入 row；跨 feature 服务协议和实现归属在 M-foundation-4 关闭。

### M-foundation-4: 能力合同与数据 adapter 归位（已关闭）

目标：把支撑能力从 feature 页面中抽出来，形成可复用、可测试、可替换的 capability 合同；同时保持 HeatMoment 数据模型只有 canonical 一套权威。

关闭证据：

- `BackupRestoreServicing` 与备份恢复值类型已从 `Features/Settings` 迁到 `Services/Backup/BackupRestoreService.swift`；`BackupRestoreView` 和 `SettingsSheetView` 只消费协议，生产 `CanonicalBackupRestoreService` 只在 App composition 注入。
- `ExportServicing` / `CanonicalExportService` 已归入 `Services/Export/ExportService.swift`；`ExportView` 不再读取 `CanonicalLibraryService` 或组装 `CanonicalExportSnapshotStore`，导出日期范围、临时目录清理和导出动作都通过同一个 capability 合同进入。
- `RootView` 和 `HeatMomentApp` 明确注入 `backupRestoreService` / `exportService`，Settings feature 不再直接创建备份或导出 concrete service。
- 导出和备份恢复仍只读/只写 canonical source，不绕过 canonical 事务边界。
- 验证通过：`./scripts/build.sh`；`./scripts/test.sh --only HeatMomentTests/BackupRestoreServiceTests --only HeatMomentTests/MarkdownExportServiceTests --only HeatMomentTests/PDFExportServiceTests`；`./scripts/test.sh --only HeatMomentUITests/MarkdownExportUITests/testSettingsExportPageGeneratesMarkdownAndShowsShareLink --only HeatMomentUITests/BackupRestoreUITests/testBackupListShowsSystemMaintainedRecoveryPointAndPreview`。

工作项：

- Backup / Recovery capability：
  - 将 `BackupRestoreServicing`、恢复点摘要、prepare restore、pending restore 相关合同移出 `Features/Settings`。
  - 保持“设置内选择恢复点 -> arm pending restore -> 冷启动 boot gate consume”的成熟流程。
  - 恢复只走 canonical recovery point 路径。
- Export capability：
  - 保留一套 `ExportRequest -> ExportSnapshot -> writer` 思路。
  - Markdown/PDF 共用 snapshot，不写 canonical store，不创建恢复点，不影响 iCloud 状态。
  - `ExportView` 只消费 `ExportServicing`；canonical snapshot adapter 与 repository 内部记录隔离，避免设置页拿 canonical row 当稳定 API。
  - 导出只走 canonical snapshot adapter。
- App composition：
  - `HeatMomentApp` / `RootView` 负责把 `CanonicalBackupRestoreService`、`CanonicalExportService` 接到设置页。
  - Settings feature 只表达入口、状态和用户动作，不装配具体 service。
- 非本阶段项：
  - `CanonicalLibraryService` 是当前唯一数据权威 facade；本阶段不为了“模板感”额外包一层平行 `LibraryService`。
  - 隐私锁、订阅、同步状态和统计/时间轴查询保持 current 的单一路径；只有出现真实复用或测试痛点时再进入单独计划项。

验收：

- Features 不直接创建 `ExportService` 或 `CanonicalBackupRestoreService`。
- 备份恢复和导出 capability contract 有稳定值类型输入输出；实现细节可以替换而不改设置页面。
- 完整备份包、本机安全点和 Markdown/PDF 阅读副本导出路径测试不回归。
- 备份恢复和导出仍不绕过 canonical 事务边界。

### M-foundation-5: 测试骨架与边界守卫（已关闭）

目标：让项目不只“现在看起来干净”，还可以长期防止边界回漂。

关闭证据：

- 新增 `scripts/check-foundation-boundaries.sh`，只读扫描 `DesignSystem` 业务语义泄漏、Feature 直接创建备份/导出 concrete service、Settings 重新定义跨能力 service protocol 等明显边界回漂。
- `scripts/README.md` 已加入边界扫描入口和“窄验证优先、阶段收口再全量”的测试策略。
- `docs/current/testing-architecture.md` 已记录当前测试入口、UI test launch arguments、边界扫描职责，以及“不为模板感提前提取 UI test robot/harness”的约束。
- 验证通过：`bash -n ./scripts/check-foundation-boundaries.sh`；`./scripts/check-foundation-boundaries.sh`；`./scripts/check-foundation-boundaries.sh -h`；`./scripts/clean.sh -h`。

工作项：

- 建立边界扫描脚本或验证步骤：
  - Foundation UI 不引用 HeatMoment 业务类型。
  - Feature 不直接 new capability concrete service。
  - Settings 不定义跨 feature 服务协议。
  - current 文档不写未来计划，plans 不伪装成已实现事实。
- 为 foundation / capability 相关改动记录最小验证入口：单元测试、窄 UI 测试或脚本验证。
- 保持“相关功能优先窄验证，阶段收口再全量 verify”的策略，避免每次 UI 微调都跑巨长全量交互。
- DEBUG UI 测试支持暂不做大规模拆分；当前项目规模下继续保留原生 XCTest/XCUITest 写法，只有出现真实重复启动参数、等待逻辑或不稳定时再提取通用 harness。

验收：

- 新增基础能力时有固定测试落点和最小验证命令。
- 边界扫描能在 review 前暴露明显依赖反向引用。
- `docs/current/testing-architecture.md` 能描述新的测试 harness 分层，计划项落地后不再留在本计划里。

### M-foundation-final: 示范骨架收口（已关闭）

目标：形成可以被未来项目参考的“骨架说明 + 目录边界 + 能力合同 + 验证方式”。

关闭证据：

- 新增 [`../current/swiftui-foundation.md`](../current/swiftui-foundation.md)，沉淀当前 App composition、Business Features、Foundation UI / Capability Contracts、Capability Internals 的依赖方向。
- current 文档说明了哪些目录通常保留、哪些 HeatMoment 业务目录应替换，以及如何新增业务 feature、基础能力、settings entry 和 root sheet。
- 验证方式已写入 current：开发中优先窄验证，阶段收口或共享基础设施变动后再按风险补 lint/build/test/verify。
- [`../current/README.md`](../current/README.md) 已加入 SwiftUI 小应用骨架入口和能力矩阵行。
- 验证通过：`./scripts/check-foundation-boundaries.sh`；文档漂移扫描无结果；`git diff --check`。

工作项：

- 在 current 文档中沉淀 as-built 架构：
  - App composition。
  - Foundation UI。
  - Foundation capabilities。
  - HeatMoment business features。
  - Infrastructure。
- 写一份“新 SwiftUI 小应用如何复用本骨架”的开发者说明：
  - 哪些目录通常保留。
  - 哪些业务目录应替换。
  - 如何新增一个基础能力。
  - 如何新增一个业务 feature。
  - 如何接入设置页入口、sheet、日期控件、导出、备份恢复、隐私锁、Pro。
  - 新增业务 feature 的接入清单：业务对象、入口、所需 capability、失败态、测试入口。
  - 新增 settings entry 的接入清单：分组、row 状态、目标详情页或 action、能力归属。
  - 新增 root sheet 的接入清单：任务层级、关闭/完成动作、是否允许嵌套、对应窄 UI 测试。
  - 哪些代码可以直接复用，哪些代码只可作为 HeatMoment 业务参考。

验收：

- 一个新业务 App 的开发者能从文档判断：保留哪些基础能力、替换哪些 HeatMoment 业务、在哪里接线、跑哪些验证。
- 新业务接入方式保持显式静态组合，不引入动态 registry、插件式 loading 或通用业务 DSL。
- HeatMoment 产品公理仍完整保留，业务体验没有被模板化稀释。
- 本计划中的已落地事实迁入 `docs/current/`；本计划只保留未完成项或关闭证据。

## Acceptance

整份计划关闭需要满足：

- 文档层级闭环：contract 文档位置明确且与 `AGENTS.md` 一致；`docs/current/` 只记录已实现事实；`docs/plans/` 只记录未完成计划和验收条件。
- 架构边界闭环：App composition、business features、foundation capability contracts、capability internals、persistence/system frameworks 的职责和依赖方向能在源码目录中对应。
- UI 骨架闭环：sheet、设置页、设置详情页、日期时间控件、按钮样式、任务容器由统一基础合同治理；HeatMoment 业务 UI 不污染 foundation UI。
- 能力合同闭环：本地数据、备份恢复、导出、隐私锁、外观语言、订阅权益、同步状态提示都有稳定调用边界；业务页面不直接装配基础设施 concrete service。
- 用户体验闭环：用户不会误解“本地存储 / 本机自动恢复点 / 导出副本 / iCloud 同步 / 面容解锁 / Pro”的关系；App 无需登录的心智保持稳定。
- 验证闭环：每个阶段都有相关单元测试、窄 UI 测试、build/lint 或边界扫描；阶段收口时再跑 `./scripts/verify.sh`。

## Review Checklist

- [ ] 是否为了复用而抽象过度，导致当前 HeatMoment 变难维护。
- [ ] 是否仍保留 SwiftUI 原生 state、environment、sheet、NavigationStack 范式。
- [ ] 是否把 Mood/Moment/Tag/Heatmap 等业务语义留在业务层。
- [ ] 是否把 GRDB、StoreKit、LocalAuthentication、FileManager 等实现细节挡在 capability 内部。
- [ ] 是否避免 Settings feature 继续变成支撑能力垃圾桶。
- [ ] 是否所有已实现事实都回写 current，而不是留在 plan 里当历史说明。
