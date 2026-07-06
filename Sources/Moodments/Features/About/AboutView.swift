import SwiftUI

/// 关于页（见 `docs/design/04-screen-specs.md` §4.16、05-design-system.md §5.3.5/§5.7）：
/// **强制亮色外观 + 固定红**，不随用户在外观主题里选择的模式/主色变化——Pro/关于页与主界面
/// 强调色语义解耦（05 §5.3.5：商业化/合规页面追求跨用户一致的转化与信任观感，不被个性化
/// 主题稀释）。设置栈内 push（08-architecture.md §2.2）。
///
/// 「关于创作者」「隐私协议」「使用条款」三张卡片对应的外部链接地址产品未给出具体值，
/// `[设计决策待确认]`：先落地可点击、可无障碍朗读的行结构，链接目标留待产品/文案阶段补齐，
/// 不臆造 URL。
struct AboutView: View {
    private static let forcedRed = Color(hex: 0xFC5447)
    private static let forcedBackground = Color(hex: 0xF2F2F7)
    private static let forcedPrimaryText = Color(hex: 0x0D0C2B)

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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Self.forcedBackground.ignoresSafeArea())
        .navigationTitle("关于心绪日记")
        .tint(Self.forcedRed)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: 0x010048))
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Moodments")
                .font(.title2.bold())
                .foregroundStyle(Self.forcedPrimaryText)
            Text("版本 \(Self.versionText)")
                .font(AppTypography.caption)
                .foregroundStyle(SemanticColor.secondaryText)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aboutHeader")
    }

    private func aboutRow(title: String, identifier: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Self.forcedPrimaryText)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(SemanticColor.secondaryText)
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
}
