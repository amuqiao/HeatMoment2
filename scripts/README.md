# scripts 维护规范

本文说明 `scripts/` 下本地入口脚本的**职责边界与维护规则**。具体参数与用法以各脚本自身 `-h` 输出为准，本文**不复制完整命令手册**（单一事实源在 `-h`）。

## 工作模型

`scripts/` 提供本仓库稳定的本地操作入口，把「环境准备 / 工程生成 / 构建 / 测试 / 规范 / 运行 / 验证 / 清理」分开，避免一个脚本承担跨领域职责。

```text
dev.sh         本地开发统一入口：路由常用脚本与模拟器 App 操作
bootstrap.sh   准备工具链（xcodegen/swiftlint/swift-format）——首次一次
gen.sh         XcodeGen 从 Project.yml 生成 Moodments.xcodeproj
build.sh       构建（Debug + 模拟器，不签名）
test.sh        XCTest/XCUITest：--unit | --ui | --all
lint.sh        swiftlint + swift-format：check（默认）| --fix
run.sh         模拟器 boot → build → install → launch，本地看界面（dev.sh run 的底层动作）
verify.sh      一次性验证 lint → build → test（本地与 CI 共用入口）
clean.sh       删除 DerivedData 与生成的 .xcodeproj
lib/           被 source 的公共 helper：common.sh（仓库根/日志/快速失败）· sim.sh（模拟器解析/状态/启动）
```

新增脚本前先判断它是否属于已有入口的子命令；只有职责边界 / 生命周期 / 安全边界不同，才新增顶层 `*.sh`。

## 入口职责

顶层 shell 入口默认只负责：定位仓库根、加载 `lib/` helper、轻量参数分发、提供稳定可读的 `-h`、调用底层命令（xcodegen / xcodebuild / swiftlint 等）。复杂逻辑下沉 `lib/`，不在入口堆业务逻辑。

## Help 规范（`-h`）

各脚本 `-h` 是命令用法的**唯一事实源**，统一 envelope（无该段则省略，但顺序固定）：

- **一句话作用** — 这个入口是什么
- **用法** — 命令行形态（含 `-h|--help`）
- **参数** — 每个位置参数/选项的含义（无参数也写「无」）
- **环境变量** — 如 `SIM_NAME`（无则写「无」）
- **副作用** — 写/装/删/启动了什么；只读要显式说明
- **不负责** — 明确划清与相邻脚本的边界
- **示例** — 最小可复制命令
- **exit code** — `0` 成功 / 非 0 快速失败

约定：`-h` 与 `--help` 等价；heredoc 用 `<<'EOF'`（不展开变量），文案里项目名写字面 `Moodments`。

## 配置与快速失败边界

- **模拟器**：默认 `iPhone 17`，用环境变量 `SIM_NAME` 覆盖（`lib/sim.sh` 唯一解析处，勿各入口重复实现）。
- **工具缺失**：`bootstrap.sh` 负责安装；其余脚本经 `require_cmd` 快速失败并提示，不 silent fallback（`lint.sh` 对未装的 lint 工具告警跳过、不阻断，是有意例外）。
- **工程缺失**：`build/test/run` 在 `.xcodeproj` 不存在时自动调 `gen.sh`。
- **不入库产物**：`.xcodeproj` / `DerivedData` 不入库，靠 `gen.sh` / 构建重建（见根 `CLAUDE.md`）。

## 修改 scripts 后的验证

改动任一脚本后至少运行与改动匹配的最小验证：

```bash
./scripts/<changed>.sh -h      # 确认 help 正常
bash -n ./scripts/<changed>.sh # 语法检查
```

改动构建/测试/运行路径或公共 helper 后，跑一次一条龙：

```bash
./scripts/verify.sh
```

## 新增/修改脚本 Checklist

- 职责是否不能并入已有入口。
- 文件名稳定、`.sh` 顶层入口。
- `-h` 是否覆盖上述 envelope（作用 / 用法 / 参数 / 环境变量 / 副作用 / 不负责 / 示例 / exit code）。
- 是否复用 `lib/common.sh`、`lib/sim.sh`，不重造仓库根定位 / 模拟器解析。
- 是否避免 silent fallback，配置/工具缺失快速失败。
- 有副作用（写/删/装/启动）是否在 `-h` 显式说明。
- 是否完成最小验证（`-h` + 必要时 `verify.sh`）。
