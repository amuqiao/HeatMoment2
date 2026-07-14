#if DEBUG
    import Foundation
    import UIKit

    /// UI 测试支持（仅 DEBUG 编译）：通过 launch arguments 让 App 使用隔离的内存 canonical runtime、
    /// 并按需预置一批记录，供依赖「可滚动/有数据」的 UI 测试使用。生产构建不含此代码。
    ///
    /// - `-uiTestReset`：使用内存 canonical runtime（与磁盘隔离，仍执行首启默认资料库预置）。
    /// - `-uiTestSeedMoments`：使用内存 canonical runtime，先执行真实默认资料库，再补足到 15 条 Moment。
    /// - `-uiTestSeedImageMoment`：使用内存 canonical runtime 并预置 1 条带 3 张合成图片的 Moment，
    ///   供图片区手势与行级删除边界验收。
    /// - `-uiTestExportForcePDFFailure`：导出页使用 DEBUG-only 坏图片 snapshot，
    ///   供 PDF 导出失败态验收，不绕过入库图片校验。
    /// - `-uiTestExportDateBoundsFailOnce`：导出页首次读取导出日期边界失败，供读取失败重试验收。
    /// - `-uiTestExportShareAutoComplete`：导出成功后自动执行分享完成回调，
    ///   避免 UI 测试依赖系统分享面板的无障碍结构。
    /// - `-uiTestExportShareFailOnce`：导出成功后首次分享返回系统错误，
    ///   供分享失败保留临时副本并重试的事务路径验收。
    /// - `-uiTestBackupPackageShareAutoComplete`：完整备份包准备完成后自动执行分享完成回调，
    ///   避免 UI 测试依赖系统分享面板的无障碍结构。
    /// - `-uiTestImageDisplayCarousel`：UI 测试隔离外观偏好中把图片展示方式预置为轮播。
    /// - `-uiTestSeedMomentQuota`：使用内存 canonical runtime 并预置 15 条 Moment（占满免费额度），
    ///   供 `QuotaBlockUITests.testSixteenthMomentBlocked` 验证第 16 篇创建被前置闸门拦截。
    /// - `-uiTestSkipDefaultLibrarySeed`：使用内存 canonical runtime 但跳过首启默认资料库预置，
    ///   供需要真正空库的测试场景使用。
    /// - `-uiTestPhotoInjection`：编辑器照片区额外展示一个调试注入按钮，直接把合成 JPEG
    ///   写入草稿（见阶段 3 计划决策1：系统 `PhotosPicker` 不在 App 无障碍树内、无法可靠自动化）。
    /// - `-uiTestBackgroundImageInjection`：外观页额外展示自定义背景图调试注入按钮，绕过系统相册 UI。
    /// - `-uiTestLocalBackupRestore`：使用磁盘隔离目录而非内存容器，启用真实本地恢复点 coordinator。
    /// - `-uiTestResetLocalBackupDisk`：清理上方磁盘隔离目录，供完整备份包 UI 测试首轮启动使用。
    /// - `-uiTestSeedLocalRecoveryPoint`：预置真实 canonical 数据和 1 个内部安全点。
    enum UITestSupport {
        /// 是否应改用内存 canonical runtime（测试隔离，不落盘、不需 iCloud 能力）。
        static var wantsInMemoryCanonicalRuntime: Bool {
            let args = ProcessInfo.processInfo.arguments
            return args.contains("-uiTestReset")
                || args.contains("-uiTestSeedMoments")
                || args.contains("-uiTestSeedImageMoment")
                || args.contains("-uiTestSeedMomentQuota")
                || args.contains("-uiTestSkipDefaultLibrarySeed")
        }

        /// 是否展示编辑器照片区的调试注入入口（见类型头部说明）。
        static var wantsPhotoInjectionHook: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestPhotoInjection")
        }

        /// 是否展示外观页自定义背景图的调试注入入口。
        static var wantsBackgroundImageInjectionHook: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestBackgroundImageInjection")
        }

        static var localBackupApplicationSupportDirectory: URL? {
            UITestLocalBackupSupport.applicationSupportDirectory
        }

        static func resetLocalBackupDirectoryIfRequested() {
            UITestLocalBackupSupport.resetDirectoryIfRequested()
        }

        /// 是否暴露任务页骨架测量 marker。只用于 UI 测试读取响应式边界；
        /// 生产 DEBUG 运行不把透明测量元素放进无障碍树。
        static var wantsTaskSurfaceMeasurementIdentifiers: Bool {
            isAnyUITestRun
        }

        /// UI 测试专用：在隔离 canonical runtime 中跳过默认 3 个真实 Moment 和 3 个默认标签。
        /// 显式空库、图片手势、满额和本地备份包磁盘夹具需要独占资料库；生产路径和普通 UI 测试仍保持首启默认资料库语义。
        static var wantsSkipDefaultLibrarySeed: Bool {
            let args = ProcessInfo.processInfo.arguments
            return args.contains("-uiTestSkipDefaultLibrarySeed")
                || args.contains("-uiTestSeedImageMoment")
                || args.contains("-uiTestSeedMomentQuota")
                || args.contains("-uiTestLocalBackupRestore")
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
        private static let appearanceTestSuiteName = "com.heatmoment.uiTestAppearance"

        /// 是否任意 `-uiTest*` 启动参数在场：外观偏好测试隔离的判定口径比
        /// `wantsInMemoryCanonicalRuntime` 更宽——照片注入 (`-uiTestPhotoInjection`)、外观保存失败
        /// (`-uiTestFailAppearanceSave`) 等场景同样需要与生产 `UserDefaults.standard` 隔离，
        /// 避免真实用户默认域被测试注入的坏值/失败态污染，也避免多次测试运行相互影响。
        private static var isAnyUITestRun: Bool {
            ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        }

        /// `-uiTestFailAppearanceSave`：外观偏好写入必失败，供 docs/current/implementation-truth.md §5.3.7 异常反馈验收
        /// （`AppearanceSaveFailureUITests`）——断言界面已乐观更新（不回滚）+ 出现对应失败提示。
        static var wantsAppearanceSaveFailure: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestFailAppearanceSave")
        }

        /// 图片展示方式 UI 测试专用：在隔离外观 store 中预置轮播，覆盖 `ThumbnailStripView`
        /// 的 `TabView(.page)` 分支与行级 swipe 的手势边界。
        static var wantsImageDisplayCarousel: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestImageDisplayCarousel")
        }

        /// PDF 导出 UI 测试专用：不写入坏图片到 canonical asset store，只在导出 snapshot
        /// provider 层注入不可解码图片，覆盖 PDF renderer 失败态。
        static var wantsExportForcePDFFailure: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestExportForcePDFFailure")
        }

        static var wantsExportDateBoundsFailOnce: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestExportDateBoundsFailOnce")
        }

        static var wantsExportShareAutoComplete: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestExportShareAutoComplete")
        }

        static var wantsExportShareFailOnce: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestExportShareFailOnce")
        }

        static var wantsBackupPackageShareAutoComplete: Bool {
            ProcessInfo.processInfo.arguments.contains("-uiTestBackupPackageShareAutoComplete")
        }

        /// UI 测试隔离：清掉上一次测试运行可能残留在 `UserDefaults.standard` 里的语言偏好
        /// （见 `LanguagePreference`）——该 key 与生产用户共用 `.standard`（未像外观偏好那样切独立
        /// 套件，因为语言偏好不涉及「必失败场景注入」，只需保证起点确定性），任意 `-uiTest*`
        /// 场景下都重置，保证每次冷启动都从确定性的默认 `.zhHans` 起步（见 `HeatMomentApp.init()`）。
        static func resetLanguagePreferenceIfUITestRun() {
            guard isAnyUITestRun else { return }
            UserDefaults.standard.removeObject(forKey: LanguagePreference.storageKey)
        }

        static func resetBackupPackageExportHistoryIfUITestRun() {
            guard isAnyUITestRun else { return }
            BackupPackageExportHistoryStore().removeExportedAt()
        }

        /// 供 `HeatMomentApp` 构造 `ThemeManager` 时选择的外观存储：任意 UI 测试场景下用隔离套件
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

        /// 若带 `-uiTestSeedMoments`，则在真实默认资料库之后补足到 `Quota.freeMomentLimit` 条 Moment。
        @MainActor
        static func seedIfRequested(_ service: CanonicalLibraryService) async {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedMoments") else { return }
            do {
                let existing = try await service.repository.totalMomentCount()
                let remaining = max(0, Quota.freeMomentLimit - existing)
                guard remaining > 0 else { return }
                for index in 0..<remaining {
                    _ = try await service.repository.createMoment(
                        title: "测试时刻 \(index + 1)",
                        bodyText: "用于 UI 测试的可滚动内容占位。",
                        occurredAt: Date(timeIntervalSinceNow: Double(-index) * 3_600),
                        mood: .normal
                    )
                }
                service.noteCanonicalChange()
            } catch {
                assertionFailure("UITest seed 失败：\(error)")
            }
        }

        /// 若带 `-uiTestSeedImageMoment` 且当前为空，则预置 1 条带 3 张图片的 Moment。
        @MainActor
        static func seedImageMomentIfRequested(_ service: CanonicalLibraryService) async {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedImageMoment") else {
                return
            }
            do {
                let existing = try await service.repository.totalMomentCount()
                guard existing == 0 else { return }
                _ = try await service.repository.createMoment(
                    title: "图片手势测试",
                    bodyText: "用于验证图片区域横向手势不会触发行级删除。",
                    occurredAt: Date(),
                    mood: .normal,
                    imageDatas: [
                        makeSyntheticPhotoData(),
                        makeSyntheticPhotoData(),
                        makeSyntheticPhotoData()
                    ]
                )
                service.noteCanonicalChange()
            } catch {
                assertionFailure("UITest 图片 Moment 预置失败：\(error)")
            }
        }

        /// 若带 `-uiTestSeedMomentQuota` 且当前为空，则预置 `Quota.freeMomentLimit` 条 Moment
        /// （占满免费额度），供第 16 篇创建被前置闸门拦截的验收使用（见类型头部说明）。
        @MainActor
        static func seedMomentQuotaIfRequested(_ service: CanonicalLibraryService) async {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedMomentQuota") else {
                return
            }
            do {
                let existing = try await service.repository.totalMomentCount()
                guard existing == 0 else { return }
                for index in 0..<Quota.freeMomentLimit {
                    _ = try await service.repository.createMoment(
                        title: "配额测试 \(index + 1)",
                        bodyText: "",
                        occurredAt: Date(timeIntervalSinceNow: Double(-index) * 3_600),
                        mood: .normal
                    )
                }
                service.noteCanonicalChange()
            } catch {
                assertionFailure("UITest 配额预置失败：\(error)")
            }
        }

        @MainActor
        static func seedCanonicalRecoveryPointIfRequested(
            _ service: CanonicalLibraryService,
            coordinator: CanonicalRecoveryCoordinator?
        ) async {
            await UITestLocalBackupSupport.seedCanonicalRecoveryPointIfRequested(
                service,
                coordinator: coordinator
            )
        }
    }

    private enum UITestLocalBackupSupport {
        private static let runIDEnvironmentKey = "HEATMOMENT_UI_TEST_LOCAL_BACKUP_RUN_ID"

        static var applicationSupportDirectory: URL? {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestLocalBackupRestore") else {
                return nil
            }
            let environment = ProcessInfo.processInfo.environment
            let runID = environment[runIDEnvironmentKey] ?? "default"
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("HeatMomentLocalBackupUITests", isDirectory: true)
                .appendingPathComponent(runID, isDirectory: true)
        }

        static func resetDirectoryIfRequested() {
            guard
                ProcessInfo.processInfo.arguments.contains("-uiTestResetLocalBackupDisk"),
                let directory = applicationSupportDirectory
            else { return }
            do {
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            } catch {
                assertionFailure("UITest 完整备份包目录清理失败：\(error)")
            }
        }

        @MainActor
        static func seedCanonicalRecoveryPointIfRequested(
            _ service: CanonicalLibraryService,
            coordinator: CanonicalRecoveryCoordinator?
        ) async {
            guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedLocalRecoveryPoint") else {
                return
            }
            guard let coordinator else {
                assertionFailure("UITest canonical 恢复点预置需要 CanonicalRecoveryCoordinator")
                return
            }
            do {
                let existing = try await service.repository.totalMomentCount()
                guard existing == 0 else { return }

                let backupMomentID = try await service.repository.createMoment(
                    title: "备份里的时刻",
                    bodyText: "用于验证资料库还原后的内容。",
                    occurredAt: Date(timeIntervalSince1970: 1_800),
                    mood: .normal,
                    now: Date(timeIntervalSince1970: 1_800)
                )
                service.noteCanonicalChange()

                try await coordinator.createRecoveryPoint(
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 2_000)
                )

                try await service.repository.purgeMoment(
                    id: backupMomentID,
                    now: Date(timeIntervalSince1970: 2_200)
                )
                _ = try await service.repository.createMoment(
                    title: "当前未恢复时刻",
                    bodyText: "用于验证恢复前后资料库已被替换。",
                    occurredAt: Date(timeIntervalSince1970: 2_400),
                    mood: .sad,
                    now: Date(timeIntervalSince1970: 2_400)
                )
                service.noteCanonicalChange()
            } catch {
                assertionFailure("UITest canonical 恢复点预置失败：\(error)")
            }
        }
    }
#endif
