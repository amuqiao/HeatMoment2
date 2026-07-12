# scripts 入口与测试收口

本文说明 `scripts/` 的入口层级、职责边界和测试运行策略。具体参数以各脚本 `-h` 为唯一命令手册，本文只维护长期稳定的使用模型。

## 入口模型

`scripts/` 分三层：

```text
日常门面：dev.sh
稳定入口：bootstrap.sh / gen.sh / build.sh / test.sh / lint.sh / check-foundation-boundaries.sh / run.sh / verify.sh / clean.sh
公共能力：lib/common.sh / lib/sim.sh
```

使用原则：

- 日常开发先用 `dev.sh`，例如 `./scripts/dev.sh run`、`./scripts/dev.sh test --unit`。
- 自动化、CI、文档证据和明确阶段验证使用稳定入口，例如 `./scripts/test.sh --ui`、`./scripts/verify.sh`。
- 公共逻辑只放 `lib/`，顶层脚本只做仓库定位、参数分发、`-h`、快速失败和调用底层工具。
- 不手敲 `xcodebuild` 作为常规流程；如果现有入口不够用，先扩展脚本入口。
- 不接受未知参数和多余参数；除 `-h|--help` 外，任何未知参数都必须在发生副作用前失败。

## 职责边界

| 入口 | 职责 | 不负责 |
| --- | --- | --- |
| `dev.sh` | 本地开发统一门面；转发构建、测试、运行、清理；提供模拟器 App 状态和启动/停止 | 新增底层构建逻辑、替代各稳定入口的 `-h` |
| `bootstrap.sh` | 首次工具链准备：`xcodegen`、`swiftlint`、`swift-format` | 安装 Xcode / Homebrew、生成工程 |
| `gen.sh` | 从 `Project.yml` 生成 `Moodments.xcodeproj` | 构建、测试、运行 |
| `build.sh` | Debug 模拟器构建，不签名 | 运行测试、安装 App |
| `test.sh` | XCTest / XCUITest 统一入口，支持套件级和定向测试 | lint、打包、真机验证 |
| `lint.sh` | `swiftlint` + `swift-format` 检查；`--fix` 才改文件 | 构建、测试 |
| `check-foundation-boundaries.sh` | 只读扫描 Foundation UI、Feature capability 和 Settings 能力归属，防止反向依赖回流 | Swift 格式、构建、XCTest/XCUITest |
| `run.sh` | 启动模拟器、构建、安装并启动 App | 跑测试、真机部署 |
| `verify.sh` | 固定一条龙：lint -> build -> test --all | 快速定向验证、安装工具链 |
| `clean.sh` | 删除 `DerivedData/` 和生成的 `.xcodeproj` | 清理模拟器数据、删除入库源码 |

新增顶层脚本前先判断它是否只是已有入口的参数。如果只是测试子集、模拟器选择或验证组合，应优先扩展 `test.sh` / `dev.sh` / `verify.sh`，不要新增平行入口。

## 测试运行策略

测试入口只收口到 `test.sh` 和 `verify.sh`：

```text
开发中定位问题       ./scripts/test.sh --only Target[/Class[/testMethod]]
开发中验证一类测试   ./scripts/test.sh --unit
界面流程改动         ./scripts/test.sh --ui
架构边界收口         ./scripts/check-foundation-boundaries.sh
阶段完成 / 提交前    ./scripts/verify.sh
```

`test.sh --only` 使用 Xcode 原生 XCTest 标识，可重复传入；因为标识里已经包含 target，不能与 `--unit` / `--ui` / `--all` 混用：

```bash
./scripts/test.sh --only MoodmentsTests/MultiTagFilterTests
./scripts/test.sh --only MoodmentsUITests/TitleCollapseFilterUITests/testFilterSheetDoesNotAutoDismissAfterChoosing
./scripts/test.sh --only MoodmentsTests/MultiTagFilterTests --only MoodmentsTests/TimelineGeometryTests
```

规则：

- 单元测试覆盖业务规则、状态计算、repository/service 生命周期，不依赖 UI。
- UI 测试覆盖关键用户流程和产品约束，不按每个按钮机械拆用例。
- 边界扫描覆盖 foundation / feature / capability / 文档路径的明显回漂，不替代编译或测试。
- 开发中可以用 `test.sh` 定向快速回归；阶段完成、计划项验收和提交前验证以 `verify.sh` 为准。
- `verify.sh` 是本地与 CI 的共同入口，固定顺序失败即停，不做“尽量继续”。

## UI 测试数据隔离

UI 测试不依赖模拟器里手工留下的数据。需要数据或系统能力注入时，通过 App 内 DEBUG-only `UITestSupport` launch arguments 进入隔离场景；完整 current 契约见 [`../docs/current/testing-architecture.md`](../docs/current/testing-architecture.md)。

`scripts/test.sh` 只负责调度 XCTest/XCUITest，不负责维护具体 seed 场景。新增 UI 测试数据场景时，优先扩展 App 侧 `UITestSupport`，不要把 fixture 参数塞进 shell 脚本。

## Help 规范

各脚本 `-h` 是命令用法的唯一事实源，统一顺序：

```text
一句话作用
用法
参数
环境变量
副作用
不负责
示例
exit code
```

`-h` 与 `--help` 等价。脚本文案中项目名写 `Moodments`。有副作用的入口必须在 `-h` 写清楚会写、删、装、启动什么。

## 修改脚本后的验证

改动任一脚本后至少运行：

```bash
./scripts/<changed>.sh -h
bash -n ./scripts/<changed>.sh
```

改动公共 helper、构建、测试、运行路径后，补充对应入口验证。影响全链路时跑：

```bash
./scripts/verify.sh
```

## 新增/修改脚本 Checklist

- 是否真的需要新增顶层入口，还是已有入口参数即可表达。
- 是否复用 `lib/common.sh` / `lib/sim.sh`，没有重复实现仓库根定位、模拟器解析、日志和快速失败。
- 是否避免 silent fallback；缺工具、缺参数、错误状态应快速失败。
- 是否拒绝未知参数和多余参数，且在写、删、装、启动前完成校验。
- 是否保留稳定 `-h` envelope。
- 是否更新本 README 中的入口职责或测试策略。
- 是否完成最小验证，并在提交或计划验收中记录。
