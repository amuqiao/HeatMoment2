import SwiftUI

/// App 入口：装配 canonical runtime（生产主流程读写权威）、集中路由 `AppRouter`、
/// 主题 `ThemeManager`、订阅 `SubscriptionService`，注入 Environment 供全树消费。
@main
struct MoodmentsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var router: AppRouter
    @State private var theme: ThemeManager
    @State private var errorPresenter = ErrorPresenter()
    @State private var localBackupRestoreState = LocalBackupRestoreState()
    @State private var subscriptionService = SubscriptionService()
    @State private var syncStatusService: SyncStatusService
    /// 冷启动尚未完成过一次 `.active` 激活：用于区分「冷启动」与「后台恢复」两类均需锁定的
    /// 时机（docs/current/implementation-truth.md §10.1.3），避免把 `.inactive` 间的瞬时切换（如下拉控制中心）误判为需要重新锁定。
    @State private var hasCompletedInitialActivation = false
    /// 是否已经历过一次「真正进入后台」（`scenePhase == .background`），独立于 `oldPhase` 判定
    /// （阶段7 review 修复）：真机从后台恢复常见路径是 `.background → .inactive → .active`，
    /// 到 `.active` 时 `onChange` 收到的 `oldPhase` 是 `.inactive` 而非 `.background`，若仍用
    /// `oldPhase == .background` 判定重锁条件会永不成立、隐私锁在真机上失效。改为独立状态
    /// 跟踪：进入 `.background` 时置位，等到之后任意一次回到 `.active` 时消费并复位，规避
    /// `.inactive` 中间态导致的判定失败。
    @State private var didEnterBackground = false
    private let canonicalLibraryService: CanonicalLibraryService
    private let canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator?
    private let backupRestoreService: (any BackupRestoreServicing)?
    private let launchRestoreResult: BackupBootRestoreResult

    /// 语言偏好（见 `LanguagePreference`、阶段7计划决策4）：与 `LanguageSettingsView` 共享同一
    /// `UserDefaults.standard` key，切换后本 `@AppStorage` 立即失效重算、驱动下方
    /// `.environment(\.locale, ...)` 即时刷新整棵树。
    @AppStorage(LanguagePreference.storageKey) private var languagePreferenceRawValue =
        LanguagePreference.zhHans.rawValue

    private var effectiveLocale: Locale {
        (LanguagePreference(rawValue: languagePreferenceRawValue) ?? .zhHans).effectiveLocale
    }

    init() {
        #if DEBUG
            // UI 测试隔离（见 `UITestSupport`）：清掉上一次测试运行可能残留在 `UserDefaults.standard`
            // 里的语言偏好（如 `LanguageSwitchUITests` 切换到 English 后未复位），保证每次 UI 测试
            // 冷启动都从确定性的默认 `.zhHans` 起步，不受同一模拟器上先前测试运行历史影响。
            UITestSupport.resetLanguagePreferenceIfUITestRun()
            UITestSupport.resetDefaultTagSeedFlagIfUITestRun()
            UITestSupport.resetLocalBackupDirectoryIfRequested()
        #endif
        // 冷启动锁定用「初始值即锁」而非 `.task` 里异步 mutate：后者会遇 SwiftUI 首帧竞态
        // （body 已用 isLocked=false 求值后 .task 才改，自定义 Binding 的首次 fullScreenCover
        // present 会被丢弃），导致隐私锁开启时冷启动锁不住（见 code review 修复）。
        _router = State(
            initialValue: {
                let router = AppRouter()
                router.isLocked = BiometricLockPreference.isEnabled()
                return router
            }())
        launchRestoreResult = Self.performPendingCanonicalRestore()

        let runtime = Self.makeRuntimeServices()
        canonicalLibraryService = runtime.canonicalLibraryService
        canonicalRecoveryCoordinator = runtime.canonicalRecoveryCoordinator
        backupRestoreService = runtime.backupRestoreService
        self.syncStatusService = runtime.syncStatusService
        // 外观持久化：生产用真实 `UserDefaults.standard`（`AppearanceStore()` 默认）；
        // DEBUG 下 UI 测试改用隔离套件（避免测试间相互污染）+ 按需注入必失败场景
        // （`-uiTestFailAppearanceSave`，见 `UITestSupport`/docs/current/implementation-truth.md §5.3.7 异常反馈验收）。
        #if DEBUG
            _theme = State(initialValue: ThemeManager(store: UITestSupport.makeAppearanceStore()))
        #else
            _theme = State(initialValue: ThemeManager())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                canonicalRecoveryCoordinator: canonicalRecoveryCoordinator,
                backupRestoreService: backupRestoreService,
                launchRestoreResult: launchRestoreResult
            )
            .environment(localBackupRestoreState)
            // 隐私锁挂在比 `rootSheet`/应用内上下文层更外层的位置（见 docs/current/implementation-truth.md §10.1.3/§2.2、
            // 阶段7计划必守约束「隐私锁挂最外层盖住 rootSheet/应用内遮罩」）：`.fullScreenCover`
            // 直接挂在 `RootView()` 之上（而非其内部），结构上包裹住 `RootView` 内部自己的
            // `.sheet` 和页面内容，解锁只置 `router.isLocked = false`，不触碰 `rootSheet`。
            //
            // **注意 modifier 顺序**：`.fullScreenCover`/`.overlay` 必须在下方 `.environment(...)`
            // 注入之前（更内层）声明，才能让锁屏/遮罩内容继承到 `theme` 等环境值——否则
            // `PrivacyLockView` 读 `@Environment(ThemeManager.self)` 会因环境缺失而 crash
            // （SwiftUI present 的内容只继承呈现修饰符所在层的环境，见 code review 修复）。
            .fullScreenCover(
                isPresented: Binding(
                    get: { router.isLocked },
                    set: { router.isLocked = $0 }
                )
            ) {
                PrivacyLockView(onUnlock: { router.isLocked = false })
                    .interactiveDismissDisabled()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { localBackupRestoreState.isPendingRestoreArmed },
                    set: { _ in }
                )
            ) {
                PendingLocalRestoreView(context: localBackupRestoreState.pendingContext)
                    .interactiveDismissDisabled()
            }
            // 多任务快照防护（docs/current/implementation-truth.md §10.1.3）：`scenePhase != .active` 时（含即将进入后台的
            // `.inactive` 瞬间）用品牌遮罩覆盖真实内容，防止敏感内容出现在多任务预览/录屏中；
            // 仅在隐私锁功能开启时才需要这层防护（未开启该功能的用户不必承受额外遮罩闪烁）。
            .overlay {
                if scenePhase != .active, BiometricLockPreference.isEnabled() {
                    PrivacyMaskView()
                }
            }
            .task {
                // 冷启动锁定已由 `router` 初始值（`init` 内 `isLocked = isEnabled()`）在首帧完成，
                // 此处不再 mutate（避免首帧竞态）；仅标记「已完成首次激活」，供下方 `onChange`
                // 区分「后台→前台重锁」与冷启动/瞬时切换（docs/current/implementation-truth.md §10.1.3）。
                hasCompletedInitialActivation = true
                subscriptionService.startObservingTransactionUpdates()
                await subscriptionService.refreshEntitlements()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // 独立状态跟踪「是否经历过真正的后台」（见 `didEnterBackground` 声明处
                // 说明），不依赖 `oldPhase == .background`——真机常见路径是
                // `.background → .inactive → .active`，到 `.active` 时 `oldPhase` 已是
                // `.inactive`，旧判定会永不成立。
                if newPhase == .background {
                    didEnterBackground = true
                    return
                }
                // 「立即锁定」策略（docs/current/implementation-truth.md §10.1.3）：只对「真正从后台恢复」触发，不对 `.inactive`
                // 之间的瞬时切换（如下拉控制中心、系统弹层，从未真正进入 `.background`）
                // 重复触发。
                guard newPhase == .active, hasCompletedInitialActivation, didEnterBackground
                else { return }
                if BiometricLockPreference.isEnabled() {
                    router.isLocked = true
                }
                Task {
                    await subscriptionService.refreshEntitlements()
                    didEnterBackground = false
                }
            }
            // Environment 注入放在最外层：包裹住上面的 `.fullScreenCover`/`.overlay`，
            // 使其 present/inline 的内容（隐私锁、遮罩）能继承到全部环境值。
            .environment(router)
            .environment(theme)
            .environment(errorPresenter)
            .environment(canonicalLibraryService)
            .environment(subscriptionService)
            .environment(syncStatusService)
            .environment(\.canonicalRecoveryCoordinator, canonicalRecoveryCoordinator)
            // 语言偏好注入（见 `LanguagePreference`、docs/current/testing-architecture.md §12.2）：
            // `.environment(\.locale, ...)` 随 `languagePreferenceRawValue` 变化自动重算，
            // 驱动整棵树重渲染；`Mood.displayName` 等无法读取 View 环境的纯值类型改用
            // `LanguagePreference.localizedString(_:)` 同步读取同一份偏好（见其头部说明），
            // 二者共享同一份真相源、不会互相脱节。
            //
            // **即时性范围**（真机/模拟器实测确认）：普通 `Text`/`Button` 字面量在已挂载
            // 页面上会随环境变化正确即时刷新（见 `LanguageSwitchUITests`）；但
            // `.navigationTitle(_:)` 桥接到 UIKit `UINavigationItem.title` 存在已知的
            // 「已挂载页面不随环境重算刷新」滞后——同屏按钮/正文已变为目标语言，导航栏标题
            // 仍可能停留旧语言，需返回上一页再重新进入（或重新呈现该任务卡片）才会刷新为
            // 新语言；这不要求杀掉/重启 App 进程，仍满足「无需重启」的契约，但不是
            // 逐字面意义的「原地」即时（阶段7计划决策4已注明的已知例外之一）。
            // 个别系统级文案（如 `NSFaceIDUsageDescription`、`CFBundleDisplayName`）由 iOS
            // 在进程启动时按系统语言一次性解析，应用内切换语言不会让它们刷新，需重启生效
            // （同决策4另一类已知例外）。
            .environment(\.locale, effectiveLocale)
            .preferredColorScheme(theme.mode == .dark ? .dark : .light)
        }
    }

    private static func makeRuntimeServices() -> RuntimeServices {
        #if DEBUG
            if UITestSupport.wantsInMemoryCanonicalRuntime {
                let canonicalLibraryService = makeInMemoryCanonicalLibraryService()
                return RuntimeServices(
                    canonicalLibraryService: canonicalLibraryService,
                    canonicalRecoveryCoordinator: nil,
                    syncStatusService: SyncStatusService(cloudKitEnabled: false),
                    backupRestoreService: nil
                )
            }
        #endif

        let canonicalRuntime = makeProductionCanonicalLibraryRuntime()
        let canonicalLibraryService = CanonicalLibraryService(runtime: canonicalRuntime)
        let canonicalRecoveryCoordinator = CanonicalRecoveryCoordinator(
            runtime: canonicalRuntime,
            appVersion: appVersion
        )
        return RuntimeServices(
            canonicalLibraryService: canonicalLibraryService,
            canonicalRecoveryCoordinator: canonicalRecoveryCoordinator,
            syncStatusService: SyncStatusService(cloudKitEnabled: hasICloudCapability),
            backupRestoreService: CanonicalBackupRestoreService(
                coordinator: canonicalRecoveryCoordinator
            )
        )
    }

    private static func performPendingCanonicalRestore() -> BackupBootRestoreResult {
        do {
            return BackupBootRestoreResult(
                result: try CanonicalBootRestoreGate.performProductionPendingRestoreIfNeeded()
            )
        } catch let error as CanonicalRestoreCriticalError {
            fatalError("本地恢复回滚失败：\(error)")
        } catch {
            return .failed(BackupBootRestoreFailure(underlying: error))
        }
    }

    private static func makeProductionCanonicalLibraryRuntime() -> CanonicalLibraryRuntime {
        do {
            return try CanonicalLibraryRuntime.makeProduction()
        } catch {
            fatalError("Canonical 本地资料库初始化失败：\(error)")
        }
    }

    private static func makeInMemoryCanonicalLibraryService() -> CanonicalLibraryService {
        do {
            return try CanonicalLibraryService(runtime: .makeInMemoryForTests())
        } catch {
            fatalError("Canonical 测试资料库初始化失败：\(error)")
        }
    }

    private static var appVersion: String {
        let dictionary = Bundle.main.infoDictionary
        let marketingVersion = dictionary?["CFBundleShortVersionString"] as? String
        let buildNumber = dictionary?["CFBundleVersion"] as? String
        return [marketingVersion, buildNumber]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static var hasICloudCapability: Bool {
        #if DEBUG
            if UITestSupport.localBackupApplicationSupportDirectory != nil {
                return false
            }
        #endif
        return FileManager.default.ubiquityIdentityToken != nil
    }

    private struct RuntimeServices {
        let canonicalLibraryService: CanonicalLibraryService
        let canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator?
        let syncStatusService: SyncStatusService
        let backupRestoreService: (any BackupRestoreServicing)?
    }
}
