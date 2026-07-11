# 测试架构真相

本文记录当前 SwiftUI 版 Moodments 已落地的测试入口、数据隔离方式和维护边界。尚未落地的快照、真实 CloudKit 自动化和导出完整验收不在本文伪装成现状；这些缺口进入 [`../plans/implementation-plan.md`](../plans/implementation-plan.md)。本地备份恢复 UI 演练已切到 canonical runtime 和磁盘隔离目录。

## 入口模型

当前测试只有两个 target：

```text
MoodmentsTests      单元 / 服务 / repository / 状态规则
MoodmentsUITests    XCUITest 用户流程和交互契约
```

命令入口收口到：

```text
./scripts/test.sh --unit       只跑 MoodmentsTests
./scripts/test.sh --ui         只跑 MoodmentsUITests
./scripts/test.sh --all        跑两个测试 target
./scripts/test.sh --only ...   跑 Xcode 原生 XCTest 标识
./scripts/verify.sh            lint -> build -> test --all
```

`dev.sh test` 只是本地门面转发到 `test.sh`。常规流程不手敲 `xcodebuild`；如果需要新的测试选择方式，优先扩展 `test.sh`。

## 单元测试数据

单元测试当前由各测试文件自己构造数据：

- SwiftData 相关测试使用内存容器或测试专用临时目录。
- `SyncStatusServiceTests` 只验证同步状态的纯逻辑推导，不证明真实 iCloud 同步、CloudKit 事件处理或多设备收敛。
- `UserDefaults` 相关测试使用独立 suite，并在 teardown 清理。
- StoreKit 测试使用 `Config/Moodments.storekit`，已知 `storekitagent` 环境握手失败时转为显式 `XCTSkip`。

当前没有统一 `Tests/MoodmentsTests/Support/` 工厂目录；内存容器、独立 `UserDefaults` suite 和临时目录 setup 分散在对应测试文件内。

## UI 测试数据

UI 测试通过 DEBUG-only `UITestSupport` 使用隔离内存 canonical runtime、固定种子或系统能力注入，不依赖模拟器内手工残留数据。

| 启动参数 | 当前语义 |
| --- | --- |
| `-uiTestReset` | 使用内存 canonical runtime，空数据起步 |
| `-uiTestSeedMoments` | 使用内存 canonical runtime 并预置可滚动时间轴 |
| `-uiTestSeedMomentQuota` | 使用内存 canonical runtime 并预置免费 Moment 额度已满 |
| `-uiTestSkipDefaultTags` | 使用内存 canonical runtime 并跳过默认标签，验证标签新增正常路径 |
| `-uiTestPhotoInjection` | 展示照片调试注入入口，绕开系统 `PhotosPicker` |
| `-uiTestBackgroundImageInjection` | 展示自定义背景图调试注入入口，绕开系统 `PhotosPicker` |
| `-uiTestLocalBackupRestore` | 使用磁盘隔离 Application Support 目录和真实本地恢复点 coordinator |
| `-uiTestResetLocalBackupDisk` | 清理本地备份 UI 测试的磁盘隔离目录，通常只在首轮启动使用 |
| `-uiTestSeedLocalRecoveryPoint` | 在磁盘隔离目录中预置 1 个可恢复点，并把当前库改成另一条记录 |
| `-uiTestForcePrivacyLockEnabled` | 强制隐私锁开启 |
| `-uiTestBiometricAlwaysSucceed` / `-uiTestBiometricAlwaysFail` | 伪造生物识别结果 |
| `-uiTestFailAppearanceSave` | 注入外观保存失败 |

任意 `-uiTest*` 场景会重置语言偏好，并让外观偏好使用隔离 suite；自定义背景图文件也写入临时隔离目录。多数 UI 测试会重置默认标签首启标记，但 `-uiTestLocalBackupRestore` 例外：它要跨两次冷启动验证真实恢复结果，不能在第二次启动前重置默认标签 seed flag 后改写刚恢复出来的资料库。只有 `-uiTestReset`、`-uiTestSeedMoments`、`-uiTestSeedMomentQuota`、`-uiTestSkipDefaultTags` 会切到内存 canonical runtime；`-uiTestLocalBackupRestore` 会使用 `MOODMENTS_UI_TEST_LOCAL_BACKUP_RUN_ID` 指定的临时磁盘目录，第二次启动必须复用同一个 run id 且不能携带 `-uiTestResetLocalBackupDisk`。`RootView` 在 DEBUG seed 与默认标签初始化完成前不会展示主页，UI 测试看到首屏入口时即可认为种子数据已就绪。

## UI 测试当前写法

当前 UI 测试已经大量使用 `accessibilityIdentifier`，并以 `waitForExistence`、谓词等待和系统可访问元素驱动交互。跨文件 helper 尚未统一：

- 各 UI 测试仍直接创建 `XCUIApplication()` 并传 `launchArguments`。
- `dismissFilterSheet`、`waitForNonexistence`、popover 收起、设置页导航等 helper 仍主要留在各测试文件内。
- 当前没有统一 `UITestApp` launcher，也没有跨文件 Robot / Screen Object 层。
