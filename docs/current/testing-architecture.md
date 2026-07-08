# 测试架构真相

本文记录当前 SwiftUI 版 Moodments 已落地的测试入口、数据隔离方式和维护边界。测试目标仍以设计层 [`../design/12-quality-assurance.md`](../design/12-quality-assurance.md) 为准；尚未落地的快照、CloudKit 自动化等不在本文伪装成现状。

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
- `UserDefaults` 相关测试使用独立 suite，并在 teardown 清理。
- StoreKit 测试使用 `Config/Moodments.storekit`，已知 `storekitagent` 环境握手失败时转为显式 `XCTSkip`。

当前没有统一 `Tests/MoodmentsTests/Support/` 工厂目录；内存容器、独立 `UserDefaults` suite 和临时目录 setup 分散在对应测试文件内。

## UI 测试数据

UI 测试通过 DEBUG-only `UITestSupport` 使用隔离内存容器、固定种子或系统能力注入，不依赖模拟器内手工残留数据。

| 启动参数 | 当前语义 |
| --- | --- |
| `-uiTestReset` | 使用内存容器，空数据起步 |
| `-uiTestSeedMoments` | 使用内存容器并预置可滚动时间轴 |
| `-uiTestSeedMomentQuota` | 使用内存容器并预置免费 Moment 额度已满 |
| `-uiTestSkipDefaultTags` | 使用内存容器并跳过默认标签，验证标签新增正常路径 |
| `-uiTestPhotoInjection` | 展示照片调试注入入口，绕开系统 `PhotosPicker` |
| `-uiTestBackgroundImageInjection` | 展示自定义背景图调试注入入口，绕开系统 `PhotosPicker` |
| `-uiTestForcePrivacyLockEnabled` | 强制隐私锁开启 |
| `-uiTestBiometricAlwaysSucceed` / `-uiTestBiometricAlwaysFail` | 伪造生物识别结果 |
| `-uiTestFailAppearanceSave` | 注入外观保存失败 |

任意 `-uiTest*` 场景会重置语言偏好、默认标签首启标记，并让外观偏好使用隔离 suite；自定义背景图文件也写入临时隔离目录。只有 `-uiTestReset`、`-uiTestSeedMoments`、`-uiTestSeedMomentQuota`、`-uiTestSkipDefaultTags` 会切到内存 SwiftData 容器；其他参数是否需要同时带 `-uiTestReset` 由测试场景决定。

## UI 测试当前写法

当前 UI 测试已经大量使用 `accessibilityIdentifier`，并以 `waitForExistence`、谓词等待和系统可访问元素驱动交互。跨文件 helper 尚未统一：

- 各 UI 测试仍直接创建 `XCUIApplication()` 并传 `launchArguments`。
- `dismissFilterSheet`、`waitForNonexistence`、popover 收起、设置页导航等 helper 仍主要留在各测试文件内。
- 当前没有统一 `UITestApp` launcher，也没有跨文件 Robot / Screen Object 层。
