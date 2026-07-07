# CLAUDE.md — 时刻 / Moodments

iOS SwiftUI 复刻 App「时刻」(App Store 商店名「心绪日记」/ 关于页 Moodments):本地优先、无自建后端的个人情绪日记。iPhone + iPad,iOS/iPadOS 17+,Swift 6（严格并发）。

## 文档四层（改动前先读；冲突时以公理层为准）

- **公理层（产品是什么 · 唯一准绳）**：`docs/product-mental-model.md` —— 9 对象 / 8 公理。任一实现或设计与它冲突，是实现/设计错了。
- **设计层 / 契约（应该怎么做的规格）**：`docs/design/`（15 份，`README.md` 是文档地图；架构见 `08`，决策记录见 `14-design-decisions.md` ADR）。前瞻规格与下游稳定契约，将来式。
- **实现真相层 / current（现在实际怎么实现的）**：`docs/current/`（`README.md` 能力/状态矩阵 + 验证基线；`implementation-truth.md` as-built 架构/数据模型落地与偏离/运行时流）。**现在式、仅已落地**；对设计的偏离记这里，不写进设计层。
- **计划层（还没做的分阶段计划）**：`docs/plans/implementation-plan.md` —— 阶段 0–7 与各阶段验收；每阶段完成后在其进度表标 ✅ 并填证据。
- **一手资料归档（不被引用）**：`docs/_source/`（真机截图 + 产品观测）。设计体系独立自维护，勿反向依赖它。

阶段完成闭环：验收通过后把该阶段 as-built 真相并入 `docs/current/`，plan 层对应阶段标 ✅ 只留验收证据（不再把已实现事实堆进设计层）。

不要在 `CLAUDE.md` 或别处复制设计事实（限额、色值、枚举等）；引用上述文档，保持单一事实源。

## 工程与命令（一律走 scripts，勿手敲 xcodebuild / 手改工程）

- 工程由 **XcodeGen** 从 `Project.yml` 生成；**`.xcodeproj` 不入库、不手改 `pbxproj`**（改工程改 `Project.yml` 后重新 `gen`）。
- 首次环境准备：`./scripts/bootstrap.sh`（装 xcodegen / swiftlint / swift-format）。
- 生成工程：`./scripts/gen.sh`
- 本地开发统一入口：`./scripts/dev.sh <command>`（如 `status` / `run` / `test --unit` / `restart`，带 `-h`）。
- 构建 / 测试 / 启动底层入口：`./scripts/build.sh` · `./scripts/test.sh [--unit|--ui|--all]` · `./scripts/run.sh`（均带 `-h`）。
- **验证入口（本地与 CI 同一个）**：`./scripts/verify.sh`（lint → build → test）。
- 复杂逻辑下沉 `scripts/lib/`；顶层脚本只做定位仓库根 + 参数分发 + 稳定 `-h` + 快速失败。

## 每阶段闭环（硬门槛）

**实现 → 同阶段写测试（单元 XCTest / UI XCUITest / 订阅 StoreKitTest）→ `./scripts/verify.sh` 通过 → 才标 ✅ 并填验收证据。**
只凭 diff 或"代码写完了"判断成功不允许；宣布完成前必须有 build/test/lint 的通过输出。测试用例已在 `implementation-plan.md` 逐阶段列为验收标准。

## 不可违背的产品公理（细节见 product-mental-model.md）

心情色一致性 · 定位 ≠ 筛选 · 删除是生命周期 · 两种浮层层级（任务卡片栈下沉入栈 / 就近浮窗同层不入栈）· 永不离开主场景 · 标签是归类非所有权 · 以发生时间组织 · 对象归属（新交互先归到某对象）。

## 关键技术约定（细节见 design/08、14）

- 架构：`@Observable` MVVM + 集中 `AppRouter`（`@MainActor @Observable`）。
- 数据：SwiftData（`@Model` + `@Query`）+ CloudKit 私有库（本地优先）。
- 并发：UI 层 `@MainActor`；写入走后台 `ModelActor`；异步加载 `.task(id:)`；跨隔离域只传值类型（如 `Moment.ID`），不传 `@Model` 引用。
- 内购 StoreKit 2（月订阅 + 终身买断）；隐私锁 LocalAuthentication。
- **排期分层**：先打磨核心（记录 / 时间轴 / 回看 / 编辑），再接支撑能力（iCloud / 面容 / 语言 / 订阅）。

## 语言

面向用户的文本默认中文；代码/命令/路径/库名保持英文原文。

# Git 规则

- 提交必须保持单一意图，不混入无关改动；跨主题改动应拆分提交。
- 提交前确认改动范围、提交主题、入口文档或规则文件同步情况。
- 提交前完成最小必要验证；无法验证时说明原因和剩余风险。
- 提交信息默认使用中文；无仓库规范时优先使用 Conventional Commits，例如 `docs:`、`feat:`、`fix:`、`refactor:`、`chore:`。
- 提交信息优先写“改了什么”和对象，不写空泛标题。
- 只在用户明确要求时提交；非明确要求下不做 `amend`，不改写历史。
- **分阶段提交、及时留回退点**：每当一处改动通过验证（`verify` 绿）即达稳定态，先提交再开始下一处较大改动；不要在未提交的通过态上继续大改。派 review/修复 agent 之前，先把当前通过态提交掉。每个实现阶段至少拆为「实现」与「review 修复」等独立提交，保证任意通过点可回退。
- **阶段边界工作区必须干净**：进入下一阶段前，本阶段全部改动已提交、`git status` 无悬留（未提交或未跟踪的本阶段产物）；不带着未提交改动跨阶段。
