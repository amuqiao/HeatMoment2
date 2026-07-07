# 测试运行 Runbook

本文说明本项目测试命令如何选择、何时启动 App、以及开发中和阶段验收时分别该跑什么。命令细节以 [`../../scripts/README.md`](../../scripts/README.md) 和各脚本 `-h` 为准；测试架构事实见 [`../current/testing-architecture.md`](../current/testing-architecture.md)。

## 先理解测试层级

`./scripts/test.sh` 是统一测试入口，下面分两类主要测试：

```text
./scripts/test.sh --unit   -> MoodmentsTests
./scripts/test.sh --ui     -> MoodmentsUITests
./scripts/test.sh --all    -> unit + ui
```

两者的关系不是“谁替代谁”，而是覆盖不同风险：

- `--unit` 保护业务规则、状态计算、repository/service 行为。
- `--ui` 保护真实 App 界面流程和用户交互。
- `--all` 用于一起确认两层都没有回归。

## 命令选择

| 场景 | 命令 | 说明 |
| --- | --- | --- |
| 改筛选规则、时间轴计算、额度、软删除生命周期 | `./scripts/test.sh --unit` | 不启动真实界面，速度快，适合开发中频繁跑。 |
| 改按钮、sheet、页面流程、滑动、输入、语言、隐私锁 | `./scripts/test.sh --ui` | 启动模拟器里的 App，用 XCUITest 驱动真实界面。 |
| 只验证某个测试类或方法 | `./scripts/test.sh --only Target[/Class[/testMethod]]` | 使用 Xcode 原生 XCTest 标识。 |
| 阶段完成、计划项验收、提交前验证 | `./scripts/verify.sh` | 固定执行 `lint -> build -> test --all`。 |

## 哪些测试会启动 App

会启动 App：

```bash
./scripts/test.sh --ui
./scripts/test.sh --only MoodmentsUITests/AppLaunchUITests
./scripts/verify.sh
```

不会启动真实 UI 流程：

```bash
./scripts/test.sh --unit
./scripts/test.sh --only MoodmentsTests/MultiTagFilterTests
```

`verify.sh` 会启动 App，因为它最终会执行 `test.sh --all`，而 `--all` 包含 UI 测试。

## 定向测试

开发中定位问题时优先用 `--only` 缩小反馈范围：

```bash
./scripts/test.sh --only MoodmentsTests/MultiTagFilterTests
./scripts/test.sh --only MoodmentsUITests/TitleCollapseFilterUITests/testCollapsedTitleTapOpensFilterSheet
```

`--only` 的标识已经包含 target，因此不要和 `--unit`、`--ui`、`--all` 混用。

## 测试类型

| 类型 | 本项目入口 | 测什么 | 是否启动 App |
| --- | --- | --- | --- |
| 单元测试 Unit | `--unit` | 纯逻辑、模型、服务、规则 | 否 |
| 集成式逻辑测试 | `--unit` | SwiftData、repository、多个对象协作 | 通常否 |
| UI 测试 XCUITest | `--ui` | 用户真实路径、sheet、滑动、输入、导航 | 是 |
| StoreKit 测试 | `--unit` 中的相关用例 | 订阅、购买、恢复、授权状态 | 不按真实 UI 流程启动 App |
| 快照 / 视觉测试 | 目前未落地 | 截图级视觉回归 | 未来按实现决定 |

## 数据隔离

测试不应依赖模拟器中手工留下的数据。

- 单元测试自己构造 SwiftData 内存容器、独立 `UserDefaults` suite 或临时目录。
- UI 测试通过 DEBUG-only launch arguments 进入固定场景，例如空数据、可滚动时间轴、额度已满、照片注入、隐私锁注入。
- 具体 launch argument 契约维护在 [`../current/testing-architecture.md`](../current/testing-architecture.md)，不要把场景参数散落到 shell 脚本里。

## 推荐工作流

开发中：

```text
先跑最窄的 --only
再跑相关层级 --unit 或 --ui
```

阶段完成：

```text
必须跑 ./scripts/verify.sh
```

如果 `verify.sh` 失败，先看失败发生在哪一层：

- `lint` 失败：修格式或 lint error。
- `build` 失败：修编译、工程生成或依赖问题。
- `test --all` 失败：根据失败 target 回到 `--unit` 或 `--ui` 定向定位。

## 常见判断

| 你改了什么 | 先跑什么 |
| --- | --- |
| 筛选 AND / 心情单选规则 | `./scripts/test.sh --only MoodmentsTests/MultiTagFilterTests` |
| 时间轴几何计算 | `./scripts/test.sh --only MoodmentsTests/TimelineGeometryTests` |
| 筛选 sheet 展示或点选行为 | `./scripts/test.sh --only MoodmentsUITests/TitleCollapseFilterUITests` |
| 热力图日/月定位 | `./scripts/test.sh --only MoodmentsUITests/LocateFilterUITests` |
| 标签管理页面 | `./scripts/test.sh --only MoodmentsUITests/TagManageUITests` |
| 删除、恢复、彻底删除 | `./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests` |
| 不确定影响面 | `./scripts/verify.sh` |
