import SwiftUI

/// 语言子页（见 `docs/design/04-screen-specs.md` §4.11「语言」行、
/// `docs/design/12-quality-assurance.md` §12.2、阶段7计划决策4）：zh-Hans / English /
/// 「跟随系统」三选一，设置栈内 push（同垃圾箱/标签管理/外观主题等子页，08-architecture.md §2.2）。
///
/// 点选立即写入 `LanguagePreference.storageKey`（`@AppStorage`），`MoodmentsApp` 读同一 key
/// 驱动 `.environment(\.locale, ...)` 即时刷新整棵树——本视图自身不持有导航/呈现状态，切换后
/// 无需用户额外确认或重启（个别系统级文案的「需重启」例外见 `MoodmentsApp` 注释）。
struct LanguageSettingsView: View {
    @Environment(ThemeManager.self) private var theme
    @AppStorage(LanguagePreference.storageKey)
    private var rawValue = LanguagePreference.zhHans.rawValue

    private var current: LanguagePreference {
        LanguagePreference(rawValue: rawValue) ?? .zhHans
    }

    var body: some View {
        TaskPageScrollView {
            TaskSurfaceSection {
                ForEach(
                    Array(LanguagePreference.allCases.enumerated()),
                    id: \.element.id
                ) { index, option in
                    row(for: option)
                    if index < LanguagePreference.allCases.count - 1 {
                        TaskSurfaceSeparator()
                    }
                }
            }
        }
        .appSheetDetailNavigationChrome("语言")
        .themedTaskContainer(theme)
    }

    private func row(for option: LanguagePreference) -> some View {
        let isSelected = current == option
        return Button {
            rawValue = option.rawValue
        } label: {
            TaskSurfaceRow {
                Text(option.displayNameKey)
                    .foregroundStyle(theme.primaryText)
            } trailing: {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("languageOption-\(option.rawValue)")
        .accessibilityLabel(Text(option.displayNameKey))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
    }
    .environment(ThemeManager())
}
