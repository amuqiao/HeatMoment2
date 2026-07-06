# 实现计划 · 时刻 / Moodments（0 → 1）

> **本文是什么**：这是从「文档就绪」到「可用 App」的**分阶段实现计划（plans 层）**。它只描述**尚未实现、要做什么、如何验收**；不重复公理与设计事实。
> - 公理层（产品是什么）：`../product-mental-model.md`
> - 设计层（怎么做的契约）：`../design/`（15 份）
> - **本层（还没做、计划怎么做）：本文**
>
> **维护规则**：某阶段完成并验收后，其"已实现事实"并入实现真相层 `docs/current/`（as-built 结构/偏离/验证基线），本文对应阶段标记为 ✅ 并只保留"验收证据"；不把已完成的当作待办堆积、也不把已实现事实堆进设计层。选型标 `[推荐默认·可调]` 的可在开工前调整。

---

## 1. Current Baseline（当前已实现且已验证）

- **文档体系**：公理层 `product-mental-model.md`（9 对象 / 8 公理）+ 设计层 `docs/design/` 15 份，经终审逐条核对 8 公理一致、grep 无残留冲突。
- **一手资料**：`docs/_source/`（真机截图 + 3 份观测文档）归档。
- **本机工具链**：Xcode 26.6、`xcodebuild`/`swift`/`xcrun`、模拟器 iPhone 17 系列可用；`xcodegen`/`swiftlint`/`swift-format` 未装（由 `scripts/bootstrap.sh` 经 brew 安装）。
- **代码 / 工程 / 脚本 / 测试**：**零**——尚不存在任何 Swift 代码、Xcode 工程、scripts、测试。

## 2. Remaining Gaps（缺什么）

- 无可构建的 App 工程与目录骨架。
- 无 `scripts/` 本地操作体系（验证 / 测试 / 启动）。
- 无领域模型、数据层、导航、界面、服务的任何实现。
- 无单元 / UI / StoreKit 测试。
- 无 CI 验证入口。

---

## 3. 技术基线与选型（开工前锁定）

| 项 | 决策 | 理由 |
|---|---|---|
| 平台 / 语言 | SwiftUI · iOS/iPadOS **17.0** · Swift 6 语言模式（严格并发） | 与 SwiftData/@Observable 起点一致；架构已按 `@MainActor`/`ModelActor`/`Sendable` 设计支撑严格并发 |
| 工程生成 | **XcodeGen（`Project.yml` → `.xcodeproj`）** `[推荐默认·可调]` | 工程可脚本化重建、避免 `pbxproj` 冲突，契合"用脚本管理"诉求；`.xcodeproj` 不入库、`Project.yml` 入库 |
| 架构 | `@Observable` MVVM + 集中 `AppRouter` + Swift Concurrency | 见 `design/08` / `14` ADR-001/002/005 |
| 持久化 / 同步 | SwiftData + CloudKit 私有库（本地优先） | 见 `design/07` / `09` |
| 内购 / 安全 | StoreKit 2、LocalAuthentication | 见 `design/11` / `10` |
| 依赖管理 | 优先零三方依赖；仅工具链（XcodeGen/SwiftLint/swift-format）经 brew | 系统能力足够（sheet 层叠、DatePicker、CloudKit 均系统原生） |
| 每阶段工作流 | **plan → 实现 → review → verify**（verify = `scripts/verify.sh` 绿） `[推荐默认·可调]` | 分阶段可审查、地基不返工 |

## 4. 工程目录与 scripts 体系（阶段 0 落地）

```
HeatMoment2/
├── Project.yml                 XcodeGen 声明（App target · Tests · entitlements · StoreKit 配置）
├── .gitignore                  忽略 *.xcodeproj / DerivedData / .build
├── scripts/
│   ├── bootstrap.sh            校验 Xcode + brew 装 xcodegen/swiftlint/swift-format（幂等，缺失即报错）
│   ├── gen.sh                  XcodeGen 生成 .xcodeproj
│   ├── build.sh                xcodebuild build（默认 Debug + iPhone 模拟器）
│   ├── test.sh                 xcodebuild test：--unit / --ui / --all（含 StoreKitTest）
│   ├── lint.sh                 swiftlint + swift-format（默认 check，--fix 修复）
│   ├── run.sh                  选/boot 模拟器 → build → install → launch（＝项目启动）
│   ├── verify.sh               lint → build → test 一条龙（本地与 CI 同一入口）
│   ├── clean.sh                清 DerivedData 与生成的 .xcodeproj
│   └── lib/
│       ├── common.sh           仓库根定位 · 日志 · set -euo pipefail · 快速失败
│       └── sim.sh              解析/选择/boot 目标模拟器（默认 iPhone 17）
├── Sources/Moodments/
│   ├── App/                    MoodmentsApp.swift · RootView.swift
│   ├── Navigation/             AppRouter.swift
│   ├── Models/                 Mood.swift · FilterCondition.swift · Quota.swift
│   ├── Persistence/            Moment/Tag/MomentImage(@Model) · ModelContainer+Config · Repositories/
│   ├── Features/               Timeline/ Editor/ Preview/ Heatmap/ Filter/ Stats/ Settings/ Tags/ Trash/ Appearance/ About/ Paywall/ Lock/
│   ├── DesignSystem/           ThemeManager · Colors · Typography · Components/
│   ├── Services/               Quota/ Sync/ Auth/ Store/
│   ├── Localization/           Localizable.xcstrings（zh-Hans / en）
│   └── Resources/              Assets.xcassets（6 主色双值 · 8 心情色 · 图标 · 插画）
├── Tests/
│   ├── MoodmentsTests/         XCTest 单元
│   └── MoodmentsUITests/       XCUITest
└── Config/
    ├── Moodments.entitlements  iCloud/CloudKit + StoreKit 能力
    └── Moodments.storekit      StoreKit 测试商品（月订阅 + 终身买断）
```

**scripts 组织原则**（借鉴 FastAPI scripts 的哲学、用 iOS 工具链实现）：领域分离；顶层入口薄、只做定位仓库根 + 加载 `lib/` + 参数分发 + 稳定 `-h`；复杂逻辑下沉 `lib/`；快速失败不 silent fallback；本地与 CI 共用 `verify.sh`。

---

## 5. Planned Work（分阶段）

> 每阶段：**目标 → 交付物 → 依赖 → 验收（scripts/verify + 具体测试用例）**。状态：⬜ 待开始 / 🟦 进行中 / ✅ 完成。

### 阶段 0 · 脚手架与 scripts ✅
- **目标**：可脚本化生成、构建、运行、验证的空 App 地基。
- **交付**：`Project.yml`、`.gitignore`、全套 `scripts/` + `lib/`、空 `MoodmentsApp`（显示占位）、Tests target 空壳、entitlements/storekit 占位、CI 用 `verify.sh`。
- **依赖**：无。
- **验收**：`./scripts/bootstrap.sh` 装齐工具；`./scripts/gen.sh` 生成工程；`./scripts/verify.sh` 全绿（lint+build+空测试）；`./scripts/run.sh` 在 iPhone 17 模拟器起空壳。

### 阶段 1 · 领域与数据契约 ✅
- **目标**：可编译、可测的数据地基。
- **交付**：`Mood`（8 情绪枚举，rawValue 契约）、`Moment`/`Tag`/`MomentImage`（`@Model`，CloudKit 兼容约束）、`ModelContainer+Config`（CloudKit 私有库装配）、`AppRouter` 骨架、`QuotaService` / `MomentRepository` / `TagRepository` 接口（`ModelActor` 后台写入）。
- **依赖**：阶段 0。
- **验收（单元测试）**：`MoodTests`（allCases=8、顺序、rawValue 稳定）；`QuotaServiceTests`（10 篇/3 图/3 标签边界：第 N 可、第 N+1 拒、Pro 不限）；`MomentLifecycleTests`（软删除置位、恢复、彻底删除、额度计数含垃圾箱与列表查询分离）；`verify.sh` 绿。

### 阶段 2 · 时间轴首屏 ✅
- **目标**：能 run 看到的第一屏。
- **交付**：`TimelineHomeView`（气泡卡片、**每情绪心情色**节点、顶部三入口、**标题两态折叠**、FAB、空态 3 条预置引导）、`TimelineModel`（`heatmapFocusDate`/`activeFilter` 双状态源占位）、`DesignSystem`（Colors 含 8 心情色 + 6 主色双值、气泡/节点/FAB 组件）。
- **依赖**：阶段 1。
- **验收（UI + 快照）**：`TimelineEmptyStateUITests`；`TitleCollapseFilterUITests`（上滑折叠后收起态标题可点、大标题态不可点）；节点按情绪着色的快照（深/浅）；`run.sh` 可见首屏。

### 阶段 3 · 记录 / 编辑 ✅
- **目标**：能真正记一条 Moment 入库。
- **交付**：`MomentEditorView`（任务卡片）、就近浮窗（`MoodPicker` / `TagPicker` / 日期 graphical / 时间 wheel，`popover`+`presentationCompactAdaptation(.popover)`）、添加照片（压缩入库 + 缩略图缓存）、保存写 SwiftData、限额拦截 → Paywall 占位。
- **依赖**：阶段 1、2。
- **验收（UI + 单元）**：`CreateMomentFlowUITests`（选情绪→标签→日期→照片→保存→出现在时间轴）；`QuotaBlockUITests`（第 4 图/第 4 标签/第 11 篇拦截）；`occurredAt` 补记单元测试（排序按发生时间）。

### 阶段 4 · 预览 + 删除生命周期 ✅
- **目标**：阅读与安全删除闭环。
- **交付**：`MomentPreviewView`（**弹出阅读卡片**，非 push）、`ImageViewerView`（fullScreenCover）、左滑删除→垃圾箱、`TrashView`（右滑恢复 / 左滑彻底删除+二次确认）。
- **依赖**：阶段 2、3。
- **验收**：`DeleteRestorePurgeUITests`（删除→垃圾箱→恢复回原发生时间位置→彻底删除释放额度）；预览为卡片非跳转的断言。

### 阶段 5 · 回看（热力图 + 统计） ✅
- **目标**：把分散记录压成年度情绪图案 + 定位。
- **交付**：`YearHeatmapView`（覆盖层，日期格=**当天最后一条心情色**）、`MoodStatsView`（心情日期分布 + 8 情绪条形）、定位与筛选双状态源接通、上下文标记（筛选标记 + 时间标记并存）。
- **依赖**：阶段 2、（多标签筛选逻辑）。
- **验收**：`LocateVsFilterTests`（定位只改滚动、不改数据集；筛选只改数据集）；`MultiTagFilterTests`（多标签 AND 交集 + 心情单选）；热力图日期着色单元测试。

### 阶段 6 · 设置 + 外观主题 ✅
- **目标**：长期管理与个性化。
- **交付**：`SettingsSheetView` + 子页（标签管理 `TagManageView` / 垃圾箱 `TrashView` / 心情统计 `MoodStatsView` / 外观主题 `AppearanceThemeView` / 关于 `AboutView`）、组合式主题（模式×主色×背景纹理×图片展示，`AppearanceStore` 逐轴持久化 + `ThemeManager` 乐观更新 + 失败提示）、统一错误通道 `ErrorPresenter`/`.userFacingErrorAlert`。
- **依赖**：阶段 2–5。
- **验收（措辞订正，见下）**：`ThemeSwitchUITests`（切**主色**时 FAB/强调随之变化，**心情色/危险色不受影响**——心情色独立于主色，这条不变量与「是否随模式切换」无关；切**模式**时画布切亮/暗、当前主色槽位不变但该主色解析出的具体色值随模式切到其亮/暗两态，**心情色也随模式切到该情绪的亮/暗态**，这是预期行为而非「切模式不变」）；`AppearanceSaveFailureUITests`（保存失败页内非模态提示 + 不回滚视觉）；`TagManageUITests`（删标签清理筛选陈旧 id、重命名、删标签不删时刻）；单元测试覆盖 `MoodColorPalette`/`AppearanceStore`/`TagRepository.renameTag`/`TimelineModel.discardFilterTag`/`ErrorPresenter`。

### 阶段 7 · 支撑能力（P1，排期后置） ✅
- **目标**：接入安全与边界能力（心智模型定位为支撑能力，不在核心成型前抢工）。
- **交付**：CloudKit 同步接通 + 同步状态展示；`BiometricLockService`（Face ID/密码锁 + 多任务遮罩）；语言切换（zh-Hans/en/跟随系统）；StoreKit（月订阅 ¥6 + 终身买断 + 核销码 + 恢复购买）。
- **依赖**：阶段 1–6。
- **验收（StoreKit + 冒烟）**：`PurchaseTests`（月订阅/终身买断/恢复/到期降级，用 `.storekit`）；双模拟器 iCloud 同步冒烟；隐私锁冷启动/回前台触发。

---

## 6. 测试策略（经 `scripts/test.sh` 统一）

| 类型 | 框架 | 覆盖（挂阶段） |
|---|---|---|
| 单元 | XCTest | Mood 契约(1)、限额(1/3)、软删除状态机(1/4)、发生时间排序(3)、多标签 AND(5)、热力图着色(5) |
| UI | XCUITest | 标题折叠筛选(2)、新建流程(3)、限额拦截(3)、删除恢复彻底删除(4)、主题切换(6) |
| StoreKit | StoreKitTest + `.storekit` | 购买/恢复/终身买断/到期降级(7) |
| 快照 | 快照比对 | 时间轴节点情绪色、深/浅模式(2/6) |

---

## 7. Acceptance（0 → 1 整体完成标准）

- `./scripts/verify.sh` 全绿（lint + build + 全部单元/UI 测试通过）。
- `./scripts/run.sh` 可完成：新建带情绪/标签/照片的 Moment → 时间轴气泡按心情色显示 → 预览/编辑 → 左滑删除进垃圾箱并恢复 → 打开年度热力图定位 → 切换外观主题。
- 8 条公理在实现中无违背（心情色一致、定位≠筛选、两种浮层、删除生命周期等）。
- P1 支撑能力（iCloud/面容/语言/订阅）在核心验收通过后接入并各自测试通过。

## 8. 风险与开放项（不阻塞 P0）

- 终身买断定价 + 双方案 Paywall 视觉（阶段 7 前需产品定）。
- 日期选中圆用主色/主文本色（阶段 3 真机实测确认）。
- 个别浅色组合 WCAG 复核（阶段 2/6 实现时用工具校）。
- `.xcodeproj` 是否入库（本计划定：不入库，靠 `Project.yml` 重建；如团队偏好入库可调）。
- **默认标签预置与 CloudKit 首次同步的重复风险**（阶段 6 前处理）：`DefaultTagSeeder` 以「Tag 表为空」为触发；接 iCloud 后新设备在下行同步完成前表仍为空，会先本地预置 工作/生活/健康 再同步下来一份、产生重复。阶段 6 接同步时需加去重/延迟预置策略。
- ~~运行时写/加载错误的用户可见反馈~~（阶段 3/4 已记，**阶段 6 已处理**）：新增统一错误通道 `Support/ErrorPresenter`（`@MainActor @Observable`，`currentError`/`report(message:underlying:)`）+ `.userFacingErrorAlert` 修饰符，在 `RootView`/`MomentEditorView` 根/`SettingsSheetView` 根各挂一份（`.alert` 不跨 sheet 边界）；编辑器 `load()`/`save()`/照片导入、时间轴删除、垃圾箱恢复/彻底删除、标签新建/重命名的写失败均已改走该通道——用户可见、debug/release 均上报（`Logger`）、不再 `assertionFailure` 中止进程、失败不伪造成功（编辑器保存失败不 dismiss、Trash/标签管理失败从仓库真相源 `reload`）。外观（`AppearanceThemeView`）保存失败按 05 §5.3.7 走页内非模态提示，不接入本通道（例外，见类型头部说明）。真正的不变量违反（如阶段5聚合 ordinality）仍 `assertionFailure`，未纳入本次改造范围。
- **图片查看器缩放后无平移**（polish）：`ImageViewerView` 已支持捏合缩放（含上界钳制）与双击，但放大后不能平移查看其他区域；04 §4.10 只要求缩放、未强制平移。补平移需与 `TabView(.page)` 分页手势做仲裁，涉及时再做。
- **时间轴末行竖线尾段悬垂**（细微视觉 polish）：贯穿式竖线覆盖每行「卡片 + 20pt 延伸段」，最后一条 Moment 节点下方仍有约 20pt 空线；需给末行传 `isLast` 收尾。
- **ThumbnailCache 在途生成去重**（低优）：async 重载在 actor 重入下，同一 `imageID` 的并发未命中请求会各自重新生成（幂等、仅重复 IO/CPU）；可用 `[UUID: Task]` 记在途任务去重。
- **热力图「选月」定位 + 整列高亮**（阶段 5 延后，见 13-open-questions #21）：现只落地「点日期格」定位 + 单格描边；04 §4.3/05 §5.4 要求「选月/选日 → 整列高亮」，月份标签可点与整列主色 12–16% 叠加待补。
- ~~筛选中标签被删除后的陈旧标记~~（**阶段 6 已处理**）：`TagManageView` 删除标签成功后调用新增的 `TimelineModel.discardFilterTag(_:)`（从 `activeFilter.tagIDs` 移除该 id，移除后两维度皆空则整体置 `nil`，不误触 `mood` 维度）；`TimelineContextMarkerBar` 同步加一层防御性跳过（`tagNamesByID` 缺失该 id 时不渲染该标记），双重保证不出现空白「#」标记。
- ~~编辑态保存重建图片的孤儿缩略图缓存~~（阶段 4 已处理：`save()`/`purge` 两处失效旧键）。
- **7 个非「正常」情绪的亮色态心情色**（阶段 6 起，待真机复核）：设计 §5.4 只采了暗态值，`MoodColorPalette` 亮态暂沿用暗态值并标 `[设计决策待确认]`；真机复核后按情绪区分两态（正常亮态 `#58BBB3` 已确认）。
- **关于页备案号**（阶段 6 起，待产品）：`AboutView` 已放占位行（`aboutBeianPlaceholder`），需产品补真实备案号；外部链接 URL（创作者/隐私/条款）同待产品，阶段 7 接。
- **`CreateMomentFlowUITests` 键盘聚焦偶发 flaky**（测试加固）：标题输入偶发「Neither element nor any descendant has keyboard focus」（模拟器键盘未及时聚焦），重跑即过；建议点输入框后显式等待键盘出现再 `typeText`，消除 CI 偶发。
- **StoreKit 购买主链路需完整环境跑一次留证**（阶段 7，环境限制）：`PurchaseTests` 的月订阅/终身买断/恢复/到期降级 4 例，因本机 `storekitagent` 握手失败（`SKInternalErrorDomain Code=3`）被 `XCTSkip`；代码逻辑已就位、不依赖 StoreKit 的「Pro→QuotaService 放行」纯逻辑单测已真跑。需在具备完整 StoreKit 测试环境的开发机跑一次留证。
- **iCloud 双设备真实同步与冲突**（阶段 7，环境限制）：单设备起动/编译/entitlements/首同步去重逻辑已验；双设备/双 iCloud 沙盒的真实下行同步与 LWW 冲突（09 §9.5、12.3）本环境做不了，待真机 + 签名环境验。
- **终身买断真实定价**（待产品）：`.storekit` 与代码用占位价 `6.00`，真实价 App Store Connect 上架时定，需回填 11-monetization / 06-domain-model / Paywall。
- **英文翻译审校 + 日期 locale 化**（阶段 7 起，待完善）：xcstrings 英文为一次性意译、未经母语/产品审校；`AppearanceThemeView` 内部选项等 17 条仅 zh（英文降级中文源文，不崩）；日期格式化仍固定 `M月d日`（7 处 `DateFormatter`），英文模式日期仍显中文字样，设计 12.2 建议改 `Date.FormatStyle` locale 感知。
- **`.navigationTitle` 语言切换滞后**（阶段 7 已知）：已挂载导航栏标题不随 `.environment(\.locale)` 即时重算，需重新呈现该任务卡片才刷新（不需重启进程）；普通 `Text`/`Button` 即时。系统级文案（`NSFaceIDUsageDescription`/`CFBundleDisplayName`）需重启生效。
- **`CFBundleLocalizations` 未接入**（阶段 7）：XcodeGen `info.properties` 需同时给 `info.path` 否则 decode 失败，本轮未接；不影响 `.environment(\.locale)` 运行时机制，仅影响 App Store/系统语言列表元信息。
- **`MomentEditorView` type_body_length**（阶段 7，非阻断）：259/250 行 swiftlint style warning，建议小幅拆分。

## 9. 进度追踪

| 阶段 | 状态 | 验收证据 |
|---|---|---|
| 0 脚手架与 scripts | ✅ 完成 | `gen`✓ · `build`✓(iPhone 17) · 单元+UI 测试✓ · `lint`✓ |
| 1 领域与数据契约 | ✅ 完成 | `verify` 绿：23 单元测试全过 · build ✓ · lint ✓；review 4 项已修（throw/排序/磁盘往返/补测） |
| 2 时间轴首屏 | ✅ 完成 | `verify` 绿：23 单元 + 5 UI 测试全过 · build ✓ · lint ✓；标题两态折叠 iOS18 `onScrollGeometryChange`/iOS17 PreferenceKey 双路径；review 两份（架构无违背 + 代码 1 必修已改）已修：错误暴露/测试隔离/formatter 缓存/折叠阈值+无障碍 |
| 3 记录/编辑 | ✅ 完成 | `verify` 绿：38 单元 + UI（CreateMomentFlow/QuotaBlock/EditorSheet 等）全过 · build ✓ · lint ✓；编辑器 + 四就近浮窗 + 图片压缩管线 + 篇数/照片/标签额度闸门 + 首启预置默认标签 + 编辑态照片增删；review 两份（架构无违背；代码 1 必修：照片额度判定收敛 QuotaService + Pro latent bug）已修；延后项入 §8 |
| 4 预览+删除生命周期 | ✅ 完成 | `verify` 绿：47 单元 + 13 UI（7 套件，新增 DeleteRestorePurge）全过 · build ✓ · lint ✓；预览弹出阅读卡片（ADR-007）+ 图片查看器（fullScreenCover）+ 时间轴 `List`+`.swipeActions` 删除 + TrashView 恢复/彻底删除 + 缩略图缓存接线 + 两处缓存失效；顺带修正时间轴竖线断裂既有缺陷；review 两份均无必须修，低风险项（.isModal/缩放钳制/解码暴露/预留标注）已修；延后项入 §8 |
| 5 回看 | ✅ 完成 | `verify` 绿：63 单元（新增 LocateVsFilterTests/MultiTagFilterTests/HeatmapMoodColorTests 共16例）+ 15 UI（8 套件，回归全过，含新增 LocateFilterUITests）全过 · build ✓ · lint ✓；`TimelineModel` 上提到 `RootView` 注入（时间轴/热力图共享同一实例）；`TimelineListView`+`TimelineQuery` 落实定位/筛选正交（谓词无 Date 参数、`scrollTargetID` 纯函数）；多标签 AND 交集内存过滤（`FilterCondition.matches`）；`MomentRepository+Aggregation` 年度聚合（`ModelActor` 后台、回传 `[Int:Mood]`/`[Mood:Int]` 值类型）；`YearHeatmapView`/`MoodStatsView`/`FilterPanelView`/`TimelineContextMarkerBar` 落地真实内容；过程中修复一处真实缺陷：容器级 `.accessibilityIdentifier` 会覆盖子元素自身 identifier（已在 4 处新文件移除容器级 id 并登记教训注释）；review 两份（架构无违背、公理2 正交性评优；代码有铁律必修）已修：聚合/网格静默降级→快速失败、网格 O(1) 重构、年份区间解耦（动态含当前年）、补真正变动 focusDate 的正交断言 + 新增 `LocateFilterUITests` 集成测试；范围简化：热力图仅落地「点日期格」定位、未落地独立「点月份标签」+「整列高亮」（见 13-open-questions #21 与 §8）；延后项入 §8 |
| 6 设置+外观 | ✅ 完成 | `verify` 绿：87 单元（新增 `MoodColorPaletteTests`/`AppearanceStoreTests`/`ErrorPresenterTests`/`TimelineModelTests` 共 20 例 + `TagRepositoryTests` 补 4 例 renameTag）+ 25 UI（11 套件，回归全过，新增 `ThemeSwitchUITests`/`AppearanceSaveFailureUITests`/`TagManageUITests`）全过 · build ✓ · lint ✓；`SettingsSheetView` 补齐 Pro 横幅（局部 sheet）+ 分组A（心情统计/标签管理/垃圾箱）+ 分组B（外观主题 + iCloud/面容/语言禁用占位）+ 关于 + 版本页脚；`AppearanceStore` 逐轴 `UserDefaults` 持久化（坏值按轴回落默认 + 计数）、`ThemeManager` 四轴 `private(set)` + 语义 setter 乐观更新、`MoodColorPalette.color(for:mode:)` 签名不含主色参数（心情色独立于主色的结构性保证）；统一错误通道 `ErrorPresenter`/`.userFacingErrorAlert` 接入编辑器/垃圾箱/时间轴删除/标签新建重命名；`TagRepository.renameTag` + `TimelineModel.discardFilterTag` 落地标签重命名与筛选陈旧 id 清理；review 两份（架构无违背、公理1 心情色独立性结构性正确；代码 1 必修）已修：TagCreateSheetView 撞名错误对用户不可见 → 改 `ErrorPresenter` 呈现宿主栈（LIFO 仅栈顶宿主呈现，根治多层 `.alert` 同挂导致的呈现链折叠）+ 补撞名可见错误 UI 测试；TagPicker 加载失败改走通道；AboutView 去 `preferredColorScheme` 改 `.toolbarColorScheme` + 补备案号占位；日志 underlying 改 `.private`；「已修正」提示改中性色；`AppearanceStore` 坏配置回写自愈；标签删除关 full-swipe；延后项入 §8 |
| 7 支撑能力(P1) | ✅ 完成 | `verify` 绿：单元 102（4 StoreKit 因本机 storekitagent 环境限制 skip）+ UI 31 全过 · build ✓ · lint ✓；StoreKit2 SubscriptionService（实时 currentEntitlements 判 Pro + 三处额度闸门经 QuotaService 解锁）+ ProPaywallView（月订阅/买断/恢复/核销码，占位价待产品）；iCloud makeCloudKitContainer（无签名回退本地不崩）+ SyncStatusService 三态 + 首同步 flag 去重；Face ID 隐私锁（fullScreenCover 最外层 + 初始值即锁 + didEnterBackground 重锁）+ 多任务遮罩；本地化 Localizable.xcstrings（zh 完整/en 核心+Paywall+错误提示，含 a11y 模板）+ 语言切换。**两轮实现 + 两批 review 修复**：代码 review 3 必须修（默认标签复活越额度/进设置主线程阻塞 1s/回前台重锁 .inactive 时序）+ 建议（照片查 Pro 去重/同步三态接入/可达性 continuation 超时/错误提示本地化）已修；架构维度由代码 review 覆盖（Pro 注入不破限额契约、隐私锁、CloudKit 回退均正面确认）。延后见 §8 |
