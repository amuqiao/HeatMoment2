import SwiftUI

struct PendingLocalRestoreView: View {
    let context: BackupPendingRestoreContext?

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ZStack {
            theme.sheetBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("恢复已准备好")
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(theme.primaryText)
                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TaskSurfaceSection(accessibilityIdentifier: "pendingLocalRestoreSection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("请完全退出并重新打开 App。")
                            .font(AppTypography.body.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                        Text("App 会在下次启动时完成恢复。为避免新内容被覆盖，当前会话已暂停继续使用。")
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                    .padding(.vertical, 12)
                }
            }
            .padding(TaskSurfaceMetrics.panelPadding)
            .frame(maxWidth: 460, alignment: .leading)
        }
        .accessibilityIdentifier("pendingLocalRestoreBlocker")
    }

    private var message: String {
        guard let context else {
            return "本机内容将在下次启动时被所选备份替换。"
        }
        var text = "本机内容将在下次启动时恢复到 \(Self.dateFormatter.string(from: context.selectedCreatedAt))。"
        if let safetyCreatedAt = context.restoreSafetyCreatedAt {
            text += " 已保存 \(Self.dateFormatter.string(from: safetyCreatedAt)) 的恢复前备份。"
        }
        return text
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
