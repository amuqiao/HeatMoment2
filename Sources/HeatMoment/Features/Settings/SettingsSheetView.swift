import SwiftUI

/// 设置根页只编排入口和设置栈内导航；具体能力实现留在各 feature / capability。
///
/// **浮层归属**（docs/current/implementation-truth.md §2.2）：本视图本身是 `router.rootSheet == .settings`
/// 驱动的任务卡片栈第一层；`MoodStatsView`/`TagManageView`/`TrashView`/`AppearanceThemeView`/
/// `AboutView` 均为本视图内 `NavigationStack` 的 push 子页（不进 Router）；Pro 横幅用**局部**
/// `.sheet(item:)` 弹 `ProPaywallView`（不改 `router.rootSheet`，否则会替换掉设置本身）。
struct SettingsSheetView: View {
    private enum SettingsRoute: Hashable {
        case appearance
        case language
        case backupRestore
        case export
        case tagManage
        case trash
        case moodStats
        case about
    }

    private struct SettingsNavigationEntry: Identifiable {
        let route: SettingsRoute
        let title: String
        let identifier: String

        var id: SettingsRoute { route }
    }

    let backupRestoreService: (any BackupRestoreServicing)?
    let exportService: any ExportServicing

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(SyncStatusService.self) private var syncStatusService

    @State private var paywallTrigger: PaywallTrigger?
    @State private var isBiometricLockEnabled = BiometricLockPreference.isEnabled()
    private let biometricService = BiometricLockService()

    init(
        backupRestoreService: (any BackupRestoreServicing)? = nil,
        exportService: any ExportServicing
    ) {
        self.backupRestoreService = backupRestoreService
        self.exportService = exportService
    }

    var body: some View {
        AppSheetScaffold {
            settingsContent
        }
    }

    private var settingsContent: some View {
        TaskPageScrollView {
            proBanner

            TaskSurfaceSection(title: "个人化", accessibilityIdentifier: "settingsPersonalSection") {
                settingsNavigationRows(personalEntries)
            }

            TaskSurfaceSection(title: "数据与安全", accessibilityIdentifier: "settingsDataSecuritySection") {
                iCloudSyncRow
                TaskSurfaceSeparator()
                settingsNavigationRows(dataSecurityEntries)
                TaskSurfaceSeparator()
                biometricLockRow
            }

            TaskSurfaceSection(title: "管理", accessibilityIdentifier: "settingsManagementSection") {
                settingsNavigationRows(managementEntries)
            }

            TaskSurfaceSection(title: "权益与关于", accessibilityIdentifier: "settingsAboutSection") {
                settingsNavigationRows(aboutEntries)
            }

            Text("版本 \(Self.versionText)")
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .appSheetRootNavigationChrome("设置")
        .sheet(item: $paywallTrigger) { trigger in
            ProPaywallView(trigger: trigger)
        }
        .navigationDestination(for: SettingsRoute.self) { route in
            settingsDestination(for: route)
        }
        .userFacingErrorAlert(errorPresenter)
        .task {
            await syncStatusService.refresh()
        }
    }

    private var personalEntries: [SettingsNavigationEntry] {
        [
            SettingsNavigationEntry(
                route: .appearance, title: "外观主题", identifier: "settingsAppearanceRow"),
            SettingsNavigationEntry(route: .language, title: "语言", identifier: "settingsLanguageRow"),
        ]
    }

    private var dataSecurityEntries: [SettingsNavigationEntry] {
        [
            SettingsNavigationEntry(
                route: .backupRestore, title: "备份与恢复", identifier: "settingsBackupRestoreRow"),
            SettingsNavigationEntry(route: .export, title: "导出", identifier: "settingsExportRow"),
        ]
    }

    private var managementEntries: [SettingsNavigationEntry] {
        [
            SettingsNavigationEntry(
                route: .tagManage, title: "标签管理", identifier: "settingsTagManageRow"),
            SettingsNavigationEntry(route: .trash, title: "垃圾箱", identifier: "settingsTrashRow"),
            SettingsNavigationEntry(
                route: .moodStats, title: "心情统计", identifier: "settingsMoodStatsRow"),
        ]
    }

    private var aboutEntries: [SettingsNavigationEntry] {
        [
            SettingsNavigationEntry(
                route: .about, title: "关于心绪日记", identifier: "settingsAboutRow")
        ]
    }

    /// Pro 会员态下横幅替换为「已是 Pro 会员」态（docs/current/implementation-truth.md §4.11，已裁决见 docs/plans/README.md #11）：
    /// `subscriptionService.isPro` 是缓存快照，仅供本行显隐/文案这类**非放行** UI 使用
    /// （权威放行判断见三处额度闸门对 `currentEntitlementIsPro()` 的现场重查，阶段7计划决策1）。
    private var proBanner: some View {
        Button {
            paywallTrigger = .banner
        } label: {
            VStack(alignment: .center, spacing: 4) {
                Text(subscriptionService.isPro ? "你已是 Pro 会员" : "立即升级成为 Pro 用户")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(theme.onCommercialText)
                Text(
                    subscriptionService.isPro
                        ? "已解锁无限日记、无限照片、无限标签"
                        : "解锁无限日记、无限照片、无限标签"
                )
                .font(AppTypography.caption)
                .foregroundStyle(theme.onCommercialText.opacity(0.86))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(TaskSurfaceMetrics.panelPadding)
            .background(
                RoundedRectangle(
                    cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                    style: .continuous
                )
                .fill(theme.commercialRed)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("settingsProBanner")
        .accessibilityLabel(
            Text(
                subscriptionService.isPro
                    ? "你已是 Pro 会员，已解锁无限日记、无限照片、无限标签"
                    : "立即升级成为 Pro 用户，解锁无限日记、无限照片、无限标签"
            )
        )
    }

    /// iCloud 状态行内展示：系统能力提示，不表达成 App 登录或账号入口。
    private var iCloudSyncRow: some View {
        TaskSurfaceRow {
            Text("数据与 iCloud")
        } trailing: {
            Text(syncStatusService.status.displayText)
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsICloudRow")
        .accessibilityLabel(Text("数据与 iCloud，\(syncStatusService.status.displayText)"))
    }

    /// 「面容解锁」行（见 docs/current/implementation-truth.md §10.1.2）：Face ID 图标 + 系统开关。设备既无生物识别也未设置任何
    /// 锁屏密码时禁用/隐藏（`biometricService.canEvaluate()` 为 `false`），避免「开了锁但永远
    /// 验证不了」的死锁态。
    @ViewBuilder
    private var biometricLockRow: some View {
        if biometricService.canEvaluate() {
            Toggle(
                isOn: Binding(
                    get: { isBiometricLockEnabled },
                    set: { newValue in
                        isBiometricLockEnabled = newValue
                        BiometricLockPreference.setEnabled(newValue)
                    }
                )
            ) {
                Label("面容解锁", systemImage: "faceid")
                    .foregroundStyle(theme.primaryText)
            }
            .tint(theme.accent)
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .frame(minHeight: TaskSurfaceMetrics.rowMinHeight)
            .accessibilityIdentifier("settingsBiometricRow")
        } else {
            disabledStatusRow(title: "面容解锁", status: "不可用", identifier: "settingsBiometricRow")
        }
    }

    private func disabledStatusRow(title: String, status: String, identifier: String) -> some View {
        TaskSurfaceRow {
            Text(title).foregroundStyle(theme.mutedText)
        } trailing: {
            Text(status)
                .font(AppTypography.caption)
                .foregroundStyle(theme.mutedText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("\(title)，\(status)"))
    }

    @ViewBuilder
    private func settingsNavigationRows(_ entries: [SettingsNavigationEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            settingsNavigationRow(entry)
            if index < entries.count - 1 {
                TaskSurfaceSeparator()
            }
        }
    }

    private func settingsNavigationRow(_ entry: SettingsNavigationEntry) -> some View {
        NavigationLink(value: entry.route) {
            TaskSurfaceRow {
                Text(entry.title).foregroundStyle(theme.primaryText)
            } trailing: {
                TaskDisclosureIndicator()
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(entry.identifier)
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .appearance:
            AppearanceThemeView()
        case .language:
            LanguageSettingsView()
        case .backupRestore:
            BackupRestoreView(backupRestoreService: backupRestoreService)
        case .export:
            ExportView(exportService: exportService)
        case .tagManage:
            TagManageView()
        case .trash:
            TrashView()
        case .moodStats:
            MoodStatsView(canonicalService: canonicalService)
        case .about:
            AboutView()
        }
    }

    private static var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#Preview {
    let canonicalService = CanonicalLibraryService.makeInMemoryForPreview()
    SettingsSheetView(
        exportService: PreviewExportService()
    )
        .environment(ThemeManager())
        .environment(ErrorPresenter())
        .environment(TimelineModel())
        .environment(SubscriptionService())
        .environment(SyncStatusService(cloudKitEnabled: false))
        .environment(canonicalService)
}
