import SwiftUI

/// 关于页（见 `docs/design/04-screen-specs.md` §4.16、05-design-system.md §5.3.5/§5.7）：
/// **强制亮色外观 + 固定红**，不随用户在外观主题里选择的模式/主色变化——Pro/关于页与主界面
/// 强调色语义解耦（05 §5.3.5：商业化/合规页面追求跨用户一致的转化与信任观感，不被个性化
/// 主题稀释）。设置栈内 push（08-architecture.md §2.2）。
///
/// 「关于创作者」「隐私协议」「使用条款」三张卡片对应的外部链接地址产品未给出具体值，
/// `[设计决策待确认]`：先落地可点击、可无障碍朗读的行结构，链接目标留待产品/文案阶段补齐，
/// 不臆造 URL。
///
/// **强制亮色的实现方式**：只用商业固定 token（`commercialBackground`/`commercialPrimaryText`/
/// `commercialRed` 等），并在本页子树局部注入 `.light` color scheme，避免设置任务容器的
/// 暗色环境泄漏到系统 row/chrome；不用 `.preferredColorScheme(_:)`，避免向上影响承载它的
/// `UIHostingController`/导航栈层级。
///
/// 「备案号」为大陆合规展示项（见 04 §4.16 内容清单），产品未给出真实备案号，
/// `[设计决策待确认]`：先落地占位行，真实号码待补齐。
struct AboutView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                aboutRow(title: "关于创作者", identifier: "aboutCreatorRow")
                aboutRow(title: "隐私协议", identifier: "aboutPrivacyRow")
                aboutRow(title: "使用条款", identifier: "aboutTermsRow")
            }
            .listRowBackground(theme.commercialPanelBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.commercialBackground.ignoresSafeArea())
        .appSheetDetailNavigationChrome("关于心绪日记")
        .environment(\.colorScheme, .light)
        .tint(theme.commercialRed)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.commercialLogoFill)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Moodments")
                .font(.title2.bold())
                .foregroundStyle(theme.commercialPrimaryText)
            Text("版本 \(Self.versionText)")
                .font(AppTypography.caption)
                .foregroundStyle(theme.commercialSecondaryText)
            // 备案号：大陆合规展示项，产品未给出真实号码，`[设计决策待确认]`——占位文案，
            // 真实号码待补齐（见 04 §4.16 内容清单）。
            Text("备案号：[设计决策待确认]")
                .font(AppTypography.caption)
                .foregroundStyle(theme.commercialSecondaryText)
                .accessibilityIdentifier("aboutBeianPlaceholder")
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aboutHeader")
    }

    private func aboutRow(title: String, identifier: String) -> some View {
        HStack {
            Text(title).foregroundStyle(theme.commercialPrimaryText)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(theme.commercialSecondaryText)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isButton)
    }

    private static var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .environment(ThemeManager())
}
