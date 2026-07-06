import SwiftData
import SwiftUI

/// 设置（见 `docs/design/04-screen-specs.md` §4.11）：Pro 横幅 + 分组卡片 A（心情统计/标签
/// 管理/垃圾箱）+ 分组卡片 B（iCloud/面容/语言禁用占位 + 外观主题）+ 关于 + 底部版本信息。
///
/// **浮层归属**（08-architecture.md §2.2）：本视图本身是 `router.rootSheet == .settings`
/// 驱动的任务卡片栈第一层；`MoodStatsView`/`TagManageView`/`TrashView`/`AppearanceThemeView`/
/// `AboutView` 均为本视图内 `NavigationStack` 的 push 子页（不进 Router）；Pro 横幅用**局部**
/// `.sheet(item:)` 弹 `ProPaywallView`（不改 `router.rootSheet`，否则会替换掉设置本身）。
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(SyncStatusService.self) private var syncStatusService

    @State private var paywallTrigger: PaywallTrigger?
    @State private var isBiometricLockEnabled = BiometricLockPreference.isEnabled()
    private let biometricService = BiometricLockService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    proBanner
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    NavigationLink("心情统计") {
                        MoodStatsView(modelContainer: modelContext.container)
                    }
                    .accessibilityIdentifier("settingsMoodStatsRow")

                    NavigationLink("标签管理") {
                        TagManageView(modelContainer: modelContext.container)
                    }
                    .accessibilityIdentifier("settingsTagManageRow")

                    NavigationLink("垃圾箱") {
                        TrashView()
                    }
                    .accessibilityIdentifier("settingsTrashRow")
                }

                Section {
                    iCloudSyncRow
                    biometricLockRow
                    disabledPlaceholderRow(title: "语言", identifier: "settingsLanguageRow")

                    NavigationLink("外观主题") {
                        AppearanceThemeView()
                    }
                    .accessibilityIdentifier("settingsAppearanceRow")
                }

                Section {
                    NavigationLink("关于心绪日记") {
                        AboutView()
                    }
                    .accessibilityIdentifier("settingsAboutRow")
                }

                Section {
                    Text("版本 \(Self.versionText)")
                        .font(AppTypography.caption)
                        .foregroundStyle(SemanticColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.sheetBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $paywallTrigger) { trigger in
                ProPaywallView(trigger: trigger)
            }
            .userFacingErrorAlert(errorPresenter)
            .task {
                syncStatusService.refresh()
            }
        }
    }

    /// Pro 会员态下横幅替换为「已是 Pro 会员」态（04 §4.11，已裁决见 13-open-questions.md #11）：
    /// `subscriptionService.isPro` 是缓存快照，仅供本行显隐/文案这类**非放行** UI 使用
    /// （权威放行判断见三处额度闸门对 `currentEntitlementIsPro()` 的现场重查，阶段7计划决策1）。
    private var proBanner: some View {
        Button {
            paywallTrigger = .banner
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(subscriptionService.isPro ? "你已是 Pro 会员" : "立即升级成为 Pro 用户")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(.white)
                Text(
                    subscriptionService.isPro
                        ? "已解锁无限日记、无限照片、无限标签"
                        : "解锁无限日记、无限照片、无限标签"
                )
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.accent))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsProBanner")
        .accessibilityLabel(Text(
            subscriptionService.isPro
                ? "你已是 Pro 会员，已解锁无限日记、无限照片、无限标签"
                : "立即升级成为 Pro 用户，解锁无限日记、无限照片、无限标签"
        ))
    }

    /// iCloud 同步状态行内展示（见 `docs/design/09-icloud-sync.md` §9.2、阶段7计划「浮层归属」：
    /// 行内展示、非 push 子页）。
    private var iCloudSyncRow: some View {
        HStack {
            Text("iCloud 数据同步").foregroundStyle(theme.primaryText)
            Spacer()
            Text(syncStatusService.status.displayText)
                .font(AppTypography.caption)
                .foregroundStyle(SemanticColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settingsICloudRow")
        .accessibilityLabel(Text("iCloud 数据同步，\(syncStatusService.status.displayText)"))
    }

    /// 「面容解锁」行（见 10 §10.1.2）：Face ID 图标 + 系统开关。设备既无生物识别也未设置任何
    /// 锁屏密码时禁用/隐藏（`biometricService.canEvaluate()` 为 `false`），避免「开了锁但永远
    /// 验证不了」的死锁态。
    @ViewBuilder
    private var biometricLockRow: some View {
        if biometricService.canEvaluate() {
            Toggle(isOn: Binding(
                get: { isBiometricLockEnabled },
                set: { newValue in
                    isBiometricLockEnabled = newValue
                    BiometricLockPreference.setEnabled(newValue)
                }
            )) {
                Label("面容解锁", systemImage: "faceid")
                    .foregroundStyle(theme.primaryText)
            }
            .tint(theme.accent)
            .accessibilityIdentifier("settingsBiometricRow")
        } else {
            disabledPlaceholderRow(title: "面容解锁", identifier: "settingsBiometricRow")
        }
    }

    private func disabledPlaceholderRow(title: String, identifier: String) -> some View {
        HStack {
            Text(title).foregroundStyle(SemanticColor.secondaryText)
            Spacer()
            Text("即将推出")
                .font(AppTypography.caption)
                .foregroundStyle(SemanticColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("\(title)，即将推出"))
    }

    private static var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#Preview {
    SettingsSheetView()
        .environment(ThemeManager())
        .environment(ErrorPresenter())
        .environment(TimelineModel())
        .environment(SubscriptionService())
        .environment(SyncStatusService(cloudKitEnabled: false))
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
