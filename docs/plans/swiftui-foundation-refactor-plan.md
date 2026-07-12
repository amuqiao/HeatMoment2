# SwiftUI 小而美应用骨架重构计划

本文是一份主动计划：目标是把 Moodments 收口成可作为后续 SwiftUI 小应用参考的基础骨架，同时不把单机日记 App 膨胀成通用框架。已实现事实以 [`../current/`](../current/README.md) 为准；产品语义以 [`../product-mental-model.md`](../product-mental-model.md) 为准；本地数据生命周期、iCloud 与 asset GC 仍归 [`implementation-plan.md`](implementation-plan.md) 管理。

## Planning Position

用户真实诉求：

- Moodments 仍是一个小而美的 Moment 记录 App，不做账号系统、不做自建后端、不做过度平台化。
- 这个项目也要成为以后 SwiftUI 小应用的示范骨架：日记、打卡、番茄日记等项目可以复用基础能力，再替换业务 feature。
- 复用的是稳定能力和组合方式，不是强行复用 Moodments 的首页、时间轴、心情、标签、热力图业务形状。
- 架构要借鉴成熟模板项目的“稳定合同 + 单向依赖 + 能力注册/装配”思想，但遵循 SwiftUI 原生范式，不照搬 FastAPI 分层命名。

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
- `Business Features` 负责 Moodments 业务：Timeline、Editor、Preview、Heatmap、Filter、Tags、Trash、Stats、Settings、Paywall 等。
- `Foundation Capability Contracts` 负责可复用能力合同：sheet 骨架、设置导航、隐私锁、外观、日期时间控件、数据读写用例、备份恢复、导出、订阅权益、测试 harness。
- `Capability Internals` 负责具体实现：GRDB/SQLite、FileAssetStore、StoreKit、LocalAuthentication、FileManager、CloudKit 后续实现。
- 业务 feature 不直接 new 基础设施 concrete service；基础能力不反向依赖业务 feature。
- `DesignSystem` 的基础容器不能读取 repository、service 或 Moodments 业务模型；业务语义组件要进入业务 feature 或业务 UI 层。

非目标：

- 本轮不把仓库改成多 App monorepo。
- 本轮默认不拆 Swift Package / 多 target；先用目录、合同和测试守住边界。只有当边界无法靠单 target 维护时，再评估独立 target。
- 本轮不实现 iCloud 同步、不扩展 Pro 商品、不重做本地数据模型；这些只在边界收口时调整归属。
- 不为了“模板感”引入 registry everywhere、复杂 DI 容器或自定义导航框架。
- 不引入动态插件、自动路由发现、通用页面 DSL、通用业务 DSL 或运行时 feature loading。
- 不把“未来可以复用”理解为复制 Moodments 的业务对象；`Moment`、`Mood`、`Tag`、`Timeline`、`Heatmap` 只能作为 Moodments 业务参考，不进入 Foundation 合同。

## Current Baseline

- 当前工程是单一 Xcode target，`Project.yml` 直接包含 `Sources/Moodments`；现有“模块”主要靠目录和约定，而不是 Swift package / target 强边界。
- 当前已落地 `@Observable` MVVM、集中 `AppRouter`、根级 sheet/fullScreenCover、`TimelineModel` 环境注入、隐私锁外层遮罩、StoreKit 订阅服务、语言和主题环境注入。
- 当前数据权威已收口到 `Canonical Repository + GRDB + SQLite + FileAssetStore`，SwiftData 已清理出主链路；本地备份、恢复点、Markdown/PDF 导出已进入 current 文档。
- 当前 sheet system 已有 `AppSheetScaffold`、`AppSheetHeaderBar`、`AppSheetActionButton`、`TaskPageScrollView`、`AppSheetNavigationChrome`，并已有针对编辑页、预览页、设置页、筛选页、标签创建页、Paywall 的入口规则。
- 当前测试入口已收口到 `./scripts/test.sh` 和 `./scripts/verify.sh`；UI 测试有 DEBUG-only 启动参数、内存 canonical runtime、磁盘隔离恢复测试和部分 StoreKit/隐私锁注入。
- 当前 `docs/current/` 已能描述 as-built 真相；`docs/plans/implementation-plan.md` 只保留 iCloud sync 与 asset GC 等未完成数据生命周期计划。

## Remaining Gaps

- 早期文档和代码注释存在过期文档路径，需要统一改到 `docs/current/`、`docs/plans/` 或 `docs/product-mental-model.md`，避免影子文档和断链误导维护。
- `DesignSystem` 同时包含基础容器和 Moodments 业务组件。`AppSheetScaffold` 这类容器可复用；`MoodNodeView`、`HeatmapGridView`、`BubbleCardView`、`MoodStatBarView` 等是业务语义 UI，不适合作为通用骨架基础层。
- 主题 token 中混有基础视觉语义和 Moodments 情绪语义。心情色是 Moodments 产品公理，不能变成所有未来 App 的基础主题合同。
- `RootView` 和 `AppRouter.RootSheet` 仍直接表达 preview/editor/settings/paywall 等 Moodments 业务路由；这对当前 App 正确，但还不是可替换业务首页的清晰 AppShell。
- `SettingsSheetView` 聚合统计、标签、垃圾箱、备份恢复、导出、语言、外观、关于、Paywall 等多类入口；设置页的信息架构已经可用，但能力归属仍容易退化成“所有支撑逻辑都塞进 Settings feature”。
- `BackupRestoreServicing` 定义在 `Features/Settings` 下；`ExportView` 直接从环境取 `CanonicalLibraryService` 并组装导出服务；这些跨 feature 能力合同的位置不够稳定。
- App-facing 类型和服务命名仍泄漏基础设施实现，如 `Canonical*` 在 feature 边界可见。内部实现可以叫 canonical，但 feature 合同应使用业务中性或能力中性名称。
- 测试支持混合了通用 harness 和 Moodments seed fixture；未来其他小 App 复用时，容易把 Moment/Tag/Mood 种子逻辑一起带走。
- 当前没有自动化边界检查。单 target 下，任何文件都能引用任何符号；如果没有简单的 `rg`/lint 规则，边界会再次漂移。

## Planned Work

### M-foundation-0: 文档路由与合同归属校准

目标：先按 `current / contract / plans` 校准文档归属，再开始移动代码，避免把未来计划写成当前事实，也避免创建第二套影子文档。

工作项：

- 复核 `AGENTS.md`、`docs/current/`、`docs/plans/` 和代码注释中的文档地图，确认文档事实源只落在当前三层职责内。
- 按 `$implementation-contract-plans` 分类现有内容：
  - `current`：已经实现的架构、运行流、数据模型、能力路径、验证基线。
  - `contract`：业务 feature 或基础能力调用方可以依赖的稳定能力边界、输入输出、状态语义。
  - `plans`：尚未完成的 gap、planned work、acceptance。
- 删除过期文档路径相关引用和描述；过期路径不得保留为兼容入口。
- 将散落在计划、current 和代码注释里的内容按归属移动或改写：current 只保留 as-built 和已实现能力边界，plans 只保留未完成工作。
- 在 current 或 plan 的最近相关页面中写清 SwiftUI 应用骨架边界，固定 `App Composition -> Business Features -> Foundation Capability Boundaries -> Capability Internals` 的单向依赖；不扩展成通用 framework 设计。
- 建立现有目录到目标层的映射表，标明哪些目录保持、哪些文件需要迁移、哪些只是重命名或换归属。
- 明确“可复用基础能力”和“Moodments 业务能力”的判断准则：
  - 能被日记、打卡、番茄日记复用的是 foundation。
  - 含 Moment、Mood、Tag、Timeline、Heatmap 产品语义的是 Moodments business。
  - 含 GRDB、StoreKit、LocalAuthentication、FileManager 的是 capability internal / infrastructure。
- 记录是否拆 target 的决策：默认不拆；先以目录规则和边界测试治理。

验收：

- 文档地图明确说明 product、current、plans 的实际文件位置；不存在与地图冲突的引用。
- current 不承诺未来能力；plans 不伪装成已实现事实。
- 过期文档路径引用扫描无结果。
- 已实现能力边界能反向映射到当前 `Sources/Moodments` 目录，不出现空泛层名。

### M-foundation-1: 稳定 AppShell 与路由表达

目标：让根应用壳只负责全局装配和呈现规则，业务首页和业务 sheet 作为可替换组合件接入。

工作项：

- 把 `RootView` 当前职责拆成可读边界：
  - app readiness / launch restore / default seed 属于 app composition。
  - root home content 属于 Moodments business feature。
  - root sheet/full screen presentation policy 属于 app shell。
- 保留 SwiftUI 原生 `.sheet(item:)`、`.fullScreenCover(item:)` 和 `NavigationStack`；不引入自定义导航框架。
- 将 `RootSheet` 的基础呈现规则与 Moodments 业务 case 分清职责。业务 case 可以继续存在，但 AppShell 文档和代码结构要表达“这里负责呈现策略”，而不是把业务页面接线散落到各处。
- 明确三类浮层合同：
  - 根级任务 sheet：预览、编辑、设置、权益说明。
  - 就地选择层：筛选、日期、时间、心情/标签字段选择。
  - 沉浸全屏：图片查看器、隐私锁、pending restore。
- 保持 Moodments 产品公理：“永不离开主场景”和“两种浮层层级”不被架构抽象破坏。

验收：

- Moodments 首页不需要承载隐私锁、主题、语言、StoreKit、恢复 pending overlay 等 App 级能力；这些能力由 App composition 统一治理。
- `RootView` 中业务 switch 的剩余部分有明确归属，未来迁移方向清楚。
- 现有预览、编辑、设置、Paywall、图片查看器、隐私锁、pending restore 行为不回归。

### M-foundation-2: 拆清 Foundation UI 与业务 UI

目标：让 sheet、容器、按钮、排版、设置列表等基础 UI 可复用；让 Moodments 的心情、热力图、气泡、时间轴语义留在业务层。

工作项：

- 将 `DesignSystem/Containers` 作为 Foundation UI 的核心候选：`AppSheetScaffold`、`AppSheetNavigationChrome`、`TaskContainerStyle`、`TaskPageScrollView` 等优先保留。
- 审计 `DesignSystem/Components`：
  - 基础组件继续留在 foundation UI。
  - `Mood`、`Moment`、`Heatmap`、`Timeline`、`Tag` 语义组件迁到 Moodments 业务 UI 区域。
- 将心情色、Mood palette、heatmap palette 与基础主题 token 拆开；基础主题只保留 App surface、task surface、semantic intent、typography、spacing 等通用能力。
- 统一 sheet 顶部按钮和导航 chrome 的使用约束，避免编辑页、预览页、设置页反复出现两套按钮样式。
- 日期、时间、滚筒、popover 锚点先按编辑页现有行为收口合同；只有当控件不含 Moment 语义、且至少被两个业务场景稳定复用时，才沉淀为 Foundation UI 控件。`occurredAt` 仍是 Moment 发生时间唯一事实。

验收：

- Foundation UI 文件不直接读取 `CanonicalLibraryService`、repository 或 Moodments service。
- Foundation UI 中不出现 `Mood`、`Moment`、`Tag`、`Heatmap`、`Timeline` 等业务模型依赖；允许业务层用 foundation 容器组装这些语义。
- Moment 编辑页顶部呼吸间隔、sheet 按钮样式、设置详情页返回样式都由同一套 sheet/container 合同约束。

### M-foundation-3: 收口 Settings 信息架构与能力入口

目标：设置页只做入口编排和详情页导航，不再成为支撑能力实现的落脚点。

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
- 设置根页没有“登录/账号”暗示；iCloud 明确是系统能力，不是 Moodments 账号。
- Settings feature 不再定义跨 feature 服务协议；协议和实现归属 capability 层。

### M-foundation-4: 能力合同与数据 adapter 归位

目标：把支撑能力从 feature 页面中抽出来，形成可复用、可测试、可替换的 capability 合同；同时保持 Moodments 数据模型只有 canonical 一套权威。

工作项：

- Library capability：
  - feature 只依赖 read model / mutation use case / value snapshot。
  - canonical repository、GRDB、SQLite、FileAssetStore 仍是内部实现。
  - feature 边界避免暴露 `Canonical*` 命名。
  - 显式化查询合同：timeline page、filter condition、export date range、trash list、stats query。
  - 根据真实必要性评估 tag AND 下推 SQL；如果当前数据量和复杂度不需要，先以合同记录限制，不为模板感过早优化。
- Backup / Recovery capability：
  - 将 `BackupRestoreServicing`、恢复点摘要、prepare restore、pending restore 相关合同移出 `Features/Settings`。
  - 保持“设置内选择恢复点 -> arm pending restore -> 冷启动 boot gate consume”的成熟流程。
- Export capability：
  - 保留一套 `ExportRequest -> ExportSnapshot -> writer` 思路。
  - Markdown/PDF 共用 snapshot，不写 canonical store，不创建恢复点，不影响 iCloud 状态。
  - Moment 业务负责 snapshot adapter；导出文件 writer 保持格式能力。
  - export snapshot adapter 与 repository 内部记录隔离，避免外部功能拿 canonical row 当稳定 API。
- Privacy Lock capability：
  - 偏好、验证、scenePhase 锁定、隐私遮罩归 app capability。
  - 设置页只消费开关状态和动作。
- Entitlement / Quota capability：
  - 展示态 `EntitlementSnapshot` 与放行态 entitlement check 分离。
  - `QuotaService` 保持纯策略，不把 UI 状态当授权事实。
- Sync indicator capability：
  - 在真实 CloudKit 同步状态机落地前，只作为系统 iCloud 能力和本地写入状态提示。
  - 不参与本地写入、导出、备份恢复或 Pro 授权判断。
- Appearance / Localization capability：
  - 外观和语言继续作为 app-wide environment 能力。
  - 文案切换的 UIKit navigation title 例外保留在 current truth，不包装成不存在的即时刷新承诺。
- 数据 adapter：
  - 将 export、backup、stats、heatmap 的 snapshot adapter 与 repository 内部记录隔离。
  - 保持 `occurredAt: Date` 为发生时间唯一事实；日期/时间控件只是编辑同一字段的两个视图。

验收：

- Features 不直接创建 `ExportService`、`CanonicalBackupRestoreService`、StoreKit session、LocalAuthentication context 或 repository。
- Capability contract 有稳定值类型输入输出；实现细节可以替换而不改业务页面。
- 本地创建、编辑、删除、恢复、导出、隐私锁、Pro 放行路径测试不回归。
- 查询合同覆盖首页时间轴、筛选、热力图、统计、垃圾箱、导出日期范围。
- 业务 adapter 能解释 Moment/Mood/Tag 到基础能力 snapshot 的映射。
- 备份恢复和导出仍不绕过 canonical 事务边界。

### M-foundation-5: 测试骨架与边界守卫

目标：让项目不只“现在看起来干净”，还可以长期防止边界回漂。

工作项：

- 拆分 DEBUG UI 测试支持：
  - 通用 launch/test harness：reset、isolated UserDefaults、in-memory runtime hook、capability injection。
  - Moodments fixture：moments、tags、quota、backup seed。
- 建立边界扫描脚本或验证步骤：
  - Foundation UI 不引用 Moodments 业务类型。
  - Feature 不直接 new capability concrete service。
  - Settings 不定义跨 feature 服务协议。
  - current 文档不写未来计划，plans 不伪装成已实现事实。
- 为每个 foundation capability 记录最小验证入口：单元测试、窄 UI 测试或脚本验证。
- 保持“相关功能优先窄验证，阶段收口再全量 verify”的策略，避免每次 UI 微调都跑巨长全量交互。

验收：

- 新增基础能力时有固定测试落点和最小验证命令。
- 边界扫描能在 review 前暴露明显依赖反向引用。
- `docs/current/testing-architecture.md` 能描述新的测试 harness 分层，计划项落地后不再留在本计划里。

### M-foundation-final: 示范骨架收口

目标：形成可以被未来项目参考的“骨架说明 + 目录边界 + 能力合同 + 验证方式”。

工作项：

- 在 current 文档中沉淀 as-built 架构：
  - App composition。
  - Foundation UI。
  - Foundation capabilities。
  - Moodments business features。
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
  - 哪些代码可以直接复用，哪些代码只可作为 Moodments 业务参考。
- 清理过时注释和旧文档引用，避免后续开发者被不存在的文档、旧架构命名或历史阶段说明误导。

验收：

- 一个新业务 App 的开发者能从文档判断：保留哪些基础能力、替换哪些 Moodments 业务、在哪里接线、跑哪些验证。
- 新业务接入方式保持显式静态组合，不引入动态 registry、插件式 loading 或通用业务 DSL。
- Moodments 产品公理仍完整保留，业务体验没有被模板化稀释。
- 本计划中的已落地事实迁入 `docs/current/`；本计划只保留未完成项或关闭证据。

## Acceptance

整份计划关闭需要满足：

- 文档层级闭环：contract 文档位置明确且与 `AGENTS.md` 一致；`docs/current/` 只记录已实现事实；`docs/plans/` 只记录未完成计划和验收条件。
- 架构边界闭环：App composition、business features、foundation capability contracts、capability internals、persistence/system frameworks 的职责和依赖方向能在源码目录中对应。
- UI 骨架闭环：sheet、设置页、设置详情页、日期时间控件、按钮样式、任务容器由统一基础合同治理；Moodments 业务 UI 不污染 foundation UI。
- 能力合同闭环：本地数据、备份恢复、导出、隐私锁、外观语言、订阅权益、同步状态提示都有稳定调用边界；业务页面不直接装配基础设施 concrete service。
- 用户体验闭环：用户不会误解“本地存储 / 本机自动恢复点 / 导出副本 / iCloud 同步 / 面容解锁 / Pro”的关系；App 无需登录的心智保持稳定。
- 验证闭环：每个阶段都有相关单元测试、窄 UI 测试、build/lint 或边界扫描；阶段收口时再跑 `./scripts/verify.sh`。

## Review Checklist

- [ ] 是否为了复用而抽象过度，导致当前 Moodments 变难维护。
- [ ] 是否仍保留 SwiftUI 原生 state、environment、sheet、NavigationStack 范式。
- [ ] 是否把 Mood/Moment/Tag/Heatmap 等业务语义留在业务层。
- [ ] 是否把 GRDB、StoreKit、LocalAuthentication、FileManager 等实现细节挡在 capability 内部。
- [ ] 是否避免 Settings feature 继续变成支撑能力垃圾桶。
- [ ] 是否所有已实现事实都回写 current，而不是留在 plan 里当历史说明。
