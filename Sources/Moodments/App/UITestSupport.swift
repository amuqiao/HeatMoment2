#if DEBUG
    import Foundation
    import SwiftData
    import UIKit

    /// UI 测试支持（仅 DEBUG 编译）：通过 launch arguments 让 App 使用隔离的内存容器、
    /// 并按需预置一批记录，供依赖「可滚动/有数据」的 UI 测试使用。生产构建不含此代码。
    ///
    /// - `-uiTestReset`：使用内存容器（空态、与磁盘隔离）。
    /// - `-uiTestSeedMoments`：使用内存容器并预置 15 条 Moment（使时间轴可滚动，用于标题折叠等验收）。
    /// - `-uiTestSeedImageMoment`：使用内存容器并预置 1 条带 3 张合成图片的 Moment，
    ///   供图片区手势与行级删除边界验收。
    /// - `-uiTestImageDisplayCarousel`：UI 测试隔离外观偏好中把图片展示方式预置为轮播。
    /// - `-uiTestSeedMomentQuota`：使用内存容器并预置 10 条 Moment（占满免费额度），
    ///   供 `QuotaBlockUITests.testEleventhMomentBlocked` 验证第 11 篇创建被前置闸门拦截。
    /// - `-uiTestSkipDefaultTags`：使用内存容器但跳过首启默认标签预置，供标签管理正常新建路径
    ///   在免费额度未占满时验收。
    /// - `-uiTestPhotoInjection`：编辑器照片区额外展示一个调试注入按钮，直接把合成 JPEG
    ///   写入草稿（见阶段 3 计划决策1：系统 `PhotosPicker` 不在 App 无障碍树内、无法可靠自动化）。
    /// - `-uiTestBackgroundImageInjection`：外观页额外展示自定义背景图调试注入按钮，绕过系统相册 UI。
    enum UITestSupport {
        /// 是否应改用内存容器（测试隔离，不落盘、不需 iCloud 能力）。
        static var wantsInMemoryContainer: Bool {
            let args = ProcessInfo.processInfo.arguments
            return args.contains("-uiTestReset")
                || args.contains("-uiTestSeedMoments")
                || args.contains("-uiTestSeedImageMoment")
                || args.contains("-uiTestSeedMomentQuota")
                || args.contains("-uiTestSkipDefaultTags")
        }

        /// 是否展示编辑器照片区的调试注入入口（见类型头部说明）。
        static var wantsPhotoInjectionHook: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestPhotoInjection")
        }

        /// 是否展示外观页自定义背景图的调试注入入口。
        static var wantsBackgroundImageInjectionHook: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestBackgroundImageInjection")
        }

        /// 标签管理 UI 测试专用：在隔离内存容器中跳过默认 3 标签预置，便于覆盖免费额度未满时的
        /// 正常新建路径。生产路径和未携带该参数的 UI 测试仍保持首启默认标签语义。
        static var wantsSkipDefaultTags: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestSkipDefaultTags")
        }

        /// 是否强制启用隐私锁（覆盖 `BiometricLockPreference` 默认关闭态，见该类型），供
        /// `PrivacyLockUITests` 在不依赖设置页开关交互的前提下验证锁生命周期时序
        /// （冷启动锁/回前台锁/后台遮罩/未验证前内容不可见）。
        static var wantsForcePrivacyLockEnabled: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestForcePrivacyLockEnabled")
        }

        /// DEBUG 冒烟注入：伪造 `BiometricLockService` 验证结果，绕开真实 Face ID/密码系统交互
        /// （系统级验证 UI 不在 App 无障碍树内，`XCUITest` 无法可靠驱动，见 `EditorPhotoSection`
        /// 头部注释同类先例）。
        /// - `-uiTestBiometricAlwaysSucceed`：验证恒成功。
        /// - `-uiTestBiometricAlwaysFail`：验证恒失败（非抛错，供失败态重试冒烟）。
        /// - 二者都不带：`nil`，`BiometricLockService` 走真实 `LAContext`。
        static var forcedBiometricOutcome: Bool? {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uiTestBiometricAlwaysSucceed") { return true }
            if args.contains("-uiTestBiometricAlwaysFail") { return false }
            return nil
        }

        /// 外观偏好测试隔离套件名（见 `makeAppearanceStore()`）。
        private static let appearanceTestSuiteName = "com.moodments.uiTestAppearance"

        /// 是否任意 `-uiTest*` 启动参数在场：外观偏好测试隔离的判定口径比
        /// `wantsInMemoryContainer` 更宽——照片注入 (`-uiTestPhotoInjection`)、外观保存失败
        /// (`-uiTestFailAppearanceSave`) 等场景同样需要与生产 `UserDefaults.standard` 隔离，
        /// 避免真实用户默认域被测试注入的坏值/失败态污染，也避免多次测试运行相互影响。
        private static var isAnyUITestRun: Bool {
            ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        }

        /// `-uiTestFailAppearanceSave`：外观偏好写入必失败，供 05 §5.3.7 异常反馈验收
        /// （`AppearanceSaveFailureUITests`）——断言界面已乐观更新（不回滚）+ 出现对应失败提示。
        static var wantsAppearanceSaveFailure: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestFailAppearanceSave")
        }

        /// 图片展示方式 UI 测试专用：在隔离外观 store 中预置轮播，覆盖 `ThumbnailStripView`
        /// 的 `TabView(.page)` 分支与行级 swipe 的手势边界。
        static var wantsImageDisplayCarousel: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestImageDisplayCarousel")
        }

        /// UI 测试隔离：清掉上一次测试运行可能残留在 `UserDefaults.standard` 里的语言偏好
        /// （见 `LanguagePreference`）——该 key 与生产用户共用 `.standard`（未像外观偏好那样切独立
        /// 套件，因为语言偏好不涉及「必失败场景注入」，只需保证起点确定性），任意 `-uiTest*`
        /// 场景下都重置，保证每次冷启动都从确定性的默认 `.zhHans` 起步（见 `MoodmentsApp.init()`）。
        static func resetLanguagePreferenceIfUITestRun() {
            guard isAnyUITestRun else { return }
            UserDefaults.standard.removeObject(forKey: LanguagePreference.storageKey)
        }

        /// UI 测试隔离：清掉上一次测试运行可能残留在 `UserDefaults.standard` 里的
        /// `DefaultTagSeeder` 「首启已完成预置」标记（见该类型头部说明）——UI 测试用的内存容器
        /// 每次冷启动 `Tag` 表都是全新的空表，但该 flag 存在真实的 `UserDefaults.standard` 域、
        /// 会跨测试运行持久化；若不重置，第二次及之后的 UI 测试运行会因 flag 已置位而跳过预置，
        /// 导致依赖「默认预置已占满额度」口径的用例（如 `QuotaBlockUITests`/`TagManageUITests`）
        /// 失败。任意 `-uiTest*` 场景下都重置，与 `resetLanguagePreferenceIfUITestRun()` 同一模式，
        /// 保证每次冷启动都从确定性的「真正首启」状态起步。
        static func resetDefaultTagSeedFlagIfUITestRun() {
            guard isAnyUITestRun else { return }
            UserDefaults.standard.removeObject(forKey: DefaultTagSeeder.hasCompletedFirstSeedKey)
        }

        /// 供 `MoodmentsApp` 构造 `ThemeManager` 时选择的外观存储：任意 UI 测试场景下用隔离套件
        /// （每次启动清空，保证起点恒为默认外观），并按需注入必失败场景；生产路径用真实
        /// `AppearanceStore()`（`UserDefaults.standard`）。
        static func makeAppearanceStore() -> AppearanceStore {
            guard isAnyUITestRun else { return AppearanceStore() }
            let suiteName = appearanceTestSuiteName
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            let customBackgroundImageDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true)
                .appendingPathComponent("Appearance", isDirectory: true)
            if FileManager.default.fileExists(atPath: customBackgroundImageDirectoryURL.path) {
                do {
                    try FileManager.default.removeItem(at: customBackgroundImageDirectoryURL)
                } catch {
                    assertionFailure("UITest 自定义背景图目录清理失败：\(error)")
                }
            }
            let store = AppearanceStore(
                defaults: defaults,
                customBackgroundImageDirectoryURL: customBackgroundImageDirectoryURL,
                simulateSaveFailure: wantsAppearanceSaveFailure
            )
            if wantsImageDisplayCarousel {
                do {
                    try store.save(
                        AppearancePreference(
                            mode: .dark,
                            accentColor: .violet,
                            backgroundTexture: .grid,
                            imageDisplayMode: .carousel
                        )
                    )
                } catch {
                    assertionFailure("UITest 轮播外观偏好预置失败：\(error)")
                }
            }
            return store
        }

        /// 生成一张极小的合成 JPEG，供 UI 测试注入编辑器草稿照片，不依赖真机相册权限/内容、
        /// 不经过 `PhotosPicker`（其系统 UI 不在 App 的无障碍树内，`XCUITest` 无法可靠驱动）。
        static func makeSyntheticPhotoData() -> Data {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
            let image = renderer.image { context in
                UIColor.systemPurple.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                assertionFailure("合成测试图片编码失败")
                return Data()
            }
            return data
        }

        /// 生成一张色块明显的合成 JPEG，供外观页自定义背景 UI 测试注入，不依赖相册权限/内容。
        static func makeSyntheticBackgroundImageData() -> Data {
            let size = CGSize(width: 96, height: 96)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
                UIColor.systemPink.setFill()
                context.fill(CGRect(x: 48, y: 48, width: 48, height: 48))
            }
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                assertionFailure("合成测试背景图编码失败")
                return Data()
            }
            return data
        }

        /// 若带 `-uiTestSeedMoments` 且当前为空，则预置 15 条 Moment。
        @MainActor
        static func seedIfRequested(_ context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedMoments") else { return }
            // 不吞错：预检查失败应显式暴露（与下方 save 的处理一致，见 CLAUDE.md 快速失败铁律）。
            let existing: Int
            do {
                existing = try context.fetchCount(FetchDescriptor<Moment>())
            } catch {
                assertionFailure("UITest seed 预检查失败：\(error)")
                return
            }
            guard existing == 0 else { return }
            for index in 0..<15 {
                let moment = Moment()
                moment.title = "测试时刻 \(index + 1)"
                moment.bodyText = "用于 UI 测试的可滚动内容占位。"
                moment.occurredAt = Date(timeIntervalSinceNow: Double(-index) * 3600)
                context.insert(moment)
            }
            do {
                try context.save()
            } catch {
                assertionFailure("UITest seed 失败：\(error)")
            }
        }

        /// 若带 `-uiTestSeedImageMoment` 且当前为空，则预置 1 条带 3 张图片的 Moment。
        @MainActor
        static func seedImageMomentIfRequested(_ context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedImageMoment") else {
                return
            }
            let existing: Int
            do {
                existing = try context.fetchCount(FetchDescriptor<Moment>())
            } catch {
                assertionFailure("UITest 图片 Moment 预置检查失败：\(error)")
                return
            }
            guard existing == 0 else { return }

            let moment = Moment()
            moment.title = "图片手势测试"
            moment.bodyText = "用于验证图片区域横向手势不会触发行级删除。"
            moment.occurredAt = Date()
            context.insert(moment)

            for index in 0..<3 {
                let image = MomentImage(
                    sortIndex: index,
                    imageData: makeSyntheticPhotoData(),
                    moment: moment
                )
                context.insert(image)
                moment.images.append(image)
            }

            do {
                try context.save()
            } catch {
                assertionFailure("UITest 图片 Moment 预置失败：\(error)")
            }
        }

        /// 若带 `-uiTestSeedMomentQuota` 且当前为空，则预置 `Quota.freeMomentLimit` 条 Moment
        /// （占满免费额度），供第 11 篇创建被前置闸门拦截的验收使用（见类型头部说明）。
        @MainActor
        static func seedMomentQuotaIfRequested(_ context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedMomentQuota") else {
                return
            }
            let existing: Int
            do {
                existing = try context.fetchCount(FetchDescriptor<Moment>())
            } catch {
                assertionFailure("UITest 配额预置检查失败：\(error)")
                return
            }
            guard existing == 0 else { return }
            for index in 0..<Quota.freeMomentLimit {
                let moment = Moment()
                moment.title = "配额测试 \(index + 1)"
                moment.occurredAt = Date(timeIntervalSinceNow: Double(-index) * 3600)
                context.insert(moment)
            }
            do {
                try context.save()
            } catch {
                assertionFailure("UITest 配额预置失败：\(error)")
            }
        }
    }
#endif
