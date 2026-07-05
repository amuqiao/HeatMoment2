# 实现计划 · 时刻 / Moodments（0 → 1）

> **本文是什么**：这是从「文档就绪」到「可用 App」的**分阶段实现计划（plans 层）**。它只描述**尚未实现、要做什么、如何验收**；不重复公理与设计事实。
> - 公理层（产品是什么）：`../product-mental-model.md`
> - 设计层（怎么做的契约）：`../design/`（15 份）
> - **本层（还没做、计划怎么做）：本文**
>
> **维护规则**：某阶段完成并验收后，其"已实现事实"归入设计层/代码，本文对应阶段标记为 ✅ 并只保留"验收证据"；不把已完成的当作待办堆积。选型标 `[推荐默认·可调]` 的可在开工前调整。

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

### 阶段 1 · 领域与数据契约 ⬜
- **目标**：可编译、可测的数据地基。
- **交付**：`Mood`（8 情绪枚举，rawValue 契约）、`Moment`/`Tag`/`MomentImage`（`@Model`，CloudKit 兼容约束）、`ModelContainer+Config`（CloudKit 私有库装配）、`AppRouter` 骨架、`QuotaService` / `MomentRepository` / `TagRepository` 接口（`ModelActor` 后台写入）。
- **依赖**：阶段 0。
- **验收（单元测试）**：`MoodTests`（allCases=8、顺序、rawValue 稳定）；`QuotaServiceTests`（10 篇/3 图/3 标签边界：第 N 可、第 N+1 拒、Pro 不限）；`MomentLifecycleTests`（软删除置位、恢复、彻底删除、额度计数含垃圾箱与列表查询分离）；`verify.sh` 绿。

### 阶段 2 · 时间轴首屏 ⬜
- **目标**：能 run 看到的第一屏。
- **交付**：`TimelineHomeView`（气泡卡片、**每情绪心情色**节点、顶部三入口、**标题两态折叠**、FAB、空态 3 条预置引导）、`TimelineModel`（`heatmapFocusDate`/`activeFilter` 双状态源占位）、`DesignSystem`（Colors 含 8 心情色 + 6 主色双值、气泡/节点/FAB 组件）。
- **依赖**：阶段 1。
- **验收（UI + 快照）**：`TimelineEmptyStateUITests`；`TitleCollapseFilterUITests`（上滑折叠后收起态标题可点、大标题态不可点）；节点按情绪着色的快照（深/浅）；`run.sh` 可见首屏。

### 阶段 3 · 记录 / 编辑 ⬜
- **目标**：能真正记一条 Moment 入库。
- **交付**：`MomentEditorView`（任务卡片）、就近浮窗（`MoodPicker` / `TagPicker` / 日期 graphical / 时间 wheel，`popover`+`presentationCompactAdaptation(.popover)`）、添加照片（压缩入库 + 缩略图缓存）、保存写 SwiftData、限额拦截 → Paywall 占位。
- **依赖**：阶段 1、2。
- **验收（UI + 单元）**：`CreateMomentFlowUITests`（选情绪→标签→日期→照片→保存→出现在时间轴）；`QuotaBlockUITests`（第 4 图/第 4 标签/第 11 篇拦截）；`occurredAt` 补记单元测试（排序按发生时间）。

### 阶段 4 · 预览 + 删除生命周期 ⬜
- **目标**：阅读与安全删除闭环。
- **交付**：`MomentPreviewView`（**弹出阅读卡片**，非 push）、`ImageViewerView`（fullScreenCover）、左滑删除→垃圾箱、`TrashView`（右滑恢复 / 左滑彻底删除+二次确认）。
- **依赖**：阶段 2、3。
- **验收**：`DeleteRestorePurgeUITests`（删除→垃圾箱→恢复回原发生时间位置→彻底删除释放额度）；预览为卡片非跳转的断言。

### 阶段 5 · 回看（热力图 + 统计） ⬜
- **目标**：把分散记录压成年度情绪图案 + 定位。
- **交付**：`YearHeatmapView`（覆盖层，日期格=**当天最后一条心情色**）、`MoodStatsView`（心情日期分布 + 8 情绪条形）、定位与筛选双状态源接通、上下文标记（筛选标记 + 时间标记并存）。
- **依赖**：阶段 2、（多标签筛选逻辑）。
- **验收**：`LocateVsFilterTests`（定位只改滚动、不改数据集；筛选只改数据集）；`MultiTagFilterTests`（多标签 AND 交集 + 心情单选）；热力图日期着色单元测试。

### 阶段 6 · 设置 + 外观主题 ⬜
- **目标**：长期管理与个性化。
- **交付**：`SettingsSheetView` + 子页（标签管理 / 垃圾箱入口 / 心情统计 / 外观主题 / 关于）、组合式主题（模式×主色×背景纹理×图片展示）、`ThemeManager`（Environment 注入 + 乐观更新 + 失败提示）。
- **依赖**：阶段 2–5。
- **验收**：`ThemeSwitchUITests`（切主色/模式即时生效、心情色/危险色不受影响）；乐观更新保存失败提示的测试。

### 阶段 7 · 支撑能力（P1，排期后置） ⬜
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

## 9. 进度追踪

| 阶段 | 状态 | 验收证据 |
|---|---|---|
| 0 脚手架与 scripts | ✅ 完成 | `gen`✓ · `build`✓(iPhone 17) · 单元+UI 测试✓ · `lint`✓ |
| 1 领域与数据契约 | ⬜ | — |
| 2 时间轴首屏 | ⬜ | — |
| 3 记录/编辑 | ⬜ | — |
| 4 预览+删除生命周期 | ⬜ | — |
| 5 回看 | ⬜ | — |
| 6 设置+外观 | ⬜ | — |
| 7 支撑能力(P1) | ⬜ | — |
