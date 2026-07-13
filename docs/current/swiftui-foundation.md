# SwiftUI 小应用骨架

本文说明 HeatMoment 当前可作为后续 SwiftUI 小应用参考的骨架。它记录已经落地的组合方式和边界，不把 HeatMoment 业务对象包装成通用框架。

## 心智模型

当前骨架采用显式静态组合：

```text
App Composition
  -> Business Features
      -> Foundation UI / Capability Contracts
          -> Capability Internals
              -> Persistence / Apple Frameworks / File System
```

- `App Composition` 负责启动、全局环境、根场景、根级 sheet、隐私锁遮罩、pending restore 遮罩和能力注入。
- `Business Features` 负责具体产品语义，例如 Moment、Mood、Tag、Timeline、Heatmap、Stats。
- `Foundation UI` 提供 sheet、任务容器、按钮、typography、主题 token 和设置页导航样式。
- `Capability Contracts` 提供业务页面可消费的稳定能力边界，例如完整备份包、本机安全点、阅读副本导出、订阅、同步状态、隐私锁偏好。
- `Capability Internals` 负责 GRDB、SQLite、FileAssetStore、StoreKit、LocalAuthentication、FileManager 等具体实现。

依赖方向只向下。业务页面可以使用 foundation UI 和 capability contract；foundation UI 不读取 HeatMoment 业务模型；Settings 不定义跨 feature service protocol；concrete service 由 App composition 注入。

## 当前目录角色

| 目录 / 文件 | 当前角色 | 复用方式 |
| --- | --- | --- |
| `Sources/HeatMoment/App/` | App composition、根级路由、runtime service 装配 | 新 App 保留模式，替换根业务场景和 root sheet case |
| `Sources/HeatMoment/DesignSystem/` | Foundation UI、主题、sheet/container、基础交互样式 | 可作为基础 UI 骨架复用 |
| `Sources/HeatMoment/Services/` | App capability contract 与实现入口 | 按能力复用或替换 concrete implementation |
| `Sources/HeatMoment/Persistence/Canonical/` | 当前本地资料库核心 | 适合同类本地优先 App 参考；新业务需按自身对象建模 |
| `Sources/HeatMoment/Features/` | HeatMoment 业务页面和业务组件 | 作为业务实现参考，不作为 foundation 直接复用 |
| `docs/current/` | 已落地事实、能力边界和验证基线 | 作为维护事实源 |
| `docs/plans/` | 未完成 gap、planned work、acceptance | 作为主动计划源 |
| `scripts/` | 工程生成、构建、测试、验证、边界扫描入口 | 可复用脚本分层和帮助文案模式 |

## 保留与替换

做新的小应用时，通常保留：

- `App` 里的 composition 思路：根场景、全局 environment、root sheet、能力注入。
- `DesignSystem` 里的 sheet system、task surface、typography、theme token 和基础按钮样式。
- `Services` 的能力合同写法：页面依赖 protocol / value type，concrete service 在 App composition 装配。
- `scripts` 的入口分层：`dev.sh` 日常门面，`test.sh` 定向测试，`verify.sh` 全量验证，`check-foundation-boundaries.sh` 边界扫描。
- `docs/current` / `docs/plans` 的文档分层。

通常替换：

- `Features/Timeline`、`Features/Editor`、`Features/Preview`、`Features/Heatmap`、`Features/Mood` 等 HeatMoment 业务 feature。
- `Mood`、`Moment`、`Tag`、`TimelineFilter`、`MoodPalette` 等业务模型和业务 palette。
- canonical repository 的业务 schema、record、query 和 mutation use case。
- UI 测试里的 HeatMoment seed fixture。

## 新增业务 Feature

新增业务 feature 时，先明确它属于哪个业务对象，再接线：

```text
业务对象
  -> Feature View / ViewModel
  -> 需要的 capability contract
  -> AppRouter 或局部 sheet/popover 入口
  -> 窄单元测试或 UI smoke
```

检查清单：

- 业务对象是否有明确归属，不把临时 UI 状态提升成全局路由。
- 是否复用 `AppSheetScaffold`、`TaskPageScrollView`、`TaskSurfaceSection` 等现有 foundation UI。
- 是否只依赖 capability contract，不直接创建 concrete service。
- 失败态是否通过已有错误展示或页面内状态表达。
- 是否有对应的最小验证入口。

## 新增基础能力

基础能力应从调用方需要的合同开始，而不是从 concrete implementation 开始：

```text
Capability Contract
  -> value input / output / error
  -> concrete service
  -> App composition injection
  -> feature consumption
  -> tests
```

当前示例：

- 完整备份包：`BackupPackageServicing` 由“备份与恢复”详情页消费，`CanonicalBackupPackageService` 由 App composition 注入。
- 本机安全点：`BackupRestoreServicing` / `CanonicalBackupRestoreService` 仍保留为内部 recovery point capability，不作为设置页主备份模型。
- 阅读副本导出：`ExportServicing` 由“阅读副本导出”详情页消费，`CanonicalExportService` 负责接入 canonical snapshot adapter。
- 同步状态：`SyncStatusService` 当前只表达系统 iCloud 能力和本地写入后的启发式状态。

基础能力不应反向依赖业务 feature。若能力需要业务数据，使用业务 adapter 把业务模型转成 capability snapshot。

## 新增 Settings Entry

设置页只做入口编排和设置栈内导航。新增 entry 时按这个顺序判断：

```text
分组
  -> row title / status / identifier
  -> toggle、inline status 或 detail route
  -> detail view 消费的 capability contract
  -> UI smoke
```

当前分组：

- 个人化：外观主题、语言。
- 数据与安全：数据与 iCloud、备份与恢复、阅读副本导出、面容解锁。
- 管理：标签管理、垃圾箱、心情统计。
- 权益与关于：关于心绪日记。

根页不承载复杂实现。需要列表、预览、失败重试或说明的能力进入详情页；轻量二值设置可留在根页。

## 新增 Root Sheet

根级任务 sheet 由 `AppRouter.rootSheet` 表达，适合预览、编辑、设置、权益说明这类任务卡片。局部选择层不要进入 root sheet。

检查清单：

- 这是根级任务，还是当前页面内部的选择层。
- 是否需要嵌套任务 sheet。
- 关闭、完成、保存动作使用哪一种 sheet chrome。
- 是否有窄 UI 测试覆盖打开、关闭和关键动作。

局部示例：

- 筛选 half-sheet 由首页 presenter 管理。
- 日期/时间、心情、标签选择由编辑页局部状态管理。
- 图片查看器由预览页局部 full-screen 管理。

## 验证方式

开发中优先窄验证：

```bash
./scripts/check-foundation-boundaries.sh
./scripts/test.sh --only HeatMomentTests/MarkdownExportServiceTests
./scripts/test.sh --only HeatMomentUITests/EditorSheetPresentationUITests/testSettingsRootHasNoExplicitCloseAndChildPageKeepsBackButton
```

阶段收口或共享基础设施变动后，再按风险补：

```bash
./scripts/lint.sh
./scripts/build.sh
./scripts/test.sh --unit
./scripts/verify.sh
```

`check-foundation-boundaries.sh` 只负责明显边界回漂，不替代 code review、编译或 XCTest。
