import SwiftUI

struct BackupRestoreView: View {
    let localBackupCoordinator: LocalBackupCoordinator?

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter

    @State private var recoveryPoints: [RecoveryPointMetadata] = []
    @State private var isLoaded = false

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "backupRestoreScrollView") {
            summarySection
            if let localBackupCoordinator {
                recoveryPointList(localBackupCoordinator)
            } else {
                unavailableSection
            }
        }
        .settingsDetailNavigationChrome("备份与恢复")
        .themedTaskContainer(theme)
        .task {
            await reload()
        }
        .userFacingErrorAlert(errorPresenter)
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "backupRestoreSummarySection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("App 会自动保留最近 3 个本机恢复点。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                Text("恢复点由系统自动维护，你可以查看和恢复，不能手动删除。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var unavailableSection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "backupRestoreUnavailableSection") {
            Text("当前模式下未启用本机自动恢复点。")
                .font(AppTypography.body)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
                .accessibilityIdentifier("backupRestoreUnavailableState")
        }
    }

    private func recoveryPointList(
        _ localBackupCoordinator: LocalBackupCoordinator
    ) -> some View {
        TaskSurfaceSection(title: "自动恢复点", accessibilityIdentifier: "recoveryPointsSection") {
            if isLoaded && recoveryPoints.isEmpty {
                Text("暂无可用恢复点")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("recoveryPointsEmptyState")
            } else {
                ForEach(Array(recoveryPoints.enumerated()), id: \.element.id) { index, metadata in
                    recoveryPointRow(metadata, coordinator: localBackupCoordinator)
                    if index < recoveryPoints.count - 1 {
                        TaskSurfaceSeparator()
                    }
                }
            }
        }
    }

    private func recoveryPointRow(
        _ metadata: RecoveryPointMetadata,
        coordinator: LocalBackupCoordinator
    ) -> some View {
        NavigationLink {
            RecoveryPointRestorePreviewView(
                metadata: metadata,
                localBackupCoordinator: coordinator
            )
        } label: {
            TaskSurfaceRow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(Self.dateFormatter.string(from: metadata.createdAt))
                            .font(AppTypography.body)
                            .foregroundStyle(theme.primaryText)
                        if metadata.status == .invalid {
                            Text("不可恢复")
                                .font(AppTypography.caption)
                                .foregroundStyle(theme.commercialRed)
                                .accessibilityIdentifier(
                                    "recoveryPointInvalidBadge-\(metadata.id.uuidString)")
                        }
                    }
                    Text(metadata.summaryText)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            } trailing: {
                if metadata.status == .available {
                    TaskDisclosureIndicator()
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(metadata.status != .available)
        .accessibilityIdentifier("recoveryPointRow-\(metadata.id.uuidString)")
    }

    private func reload() async {
        guard let localBackupCoordinator else {
            isLoaded = true
            return
        }
        do {
            recoveryPoints = try await localBackupCoordinator.listRecoveryPoints()
        } catch {
            errorPresenter.report(message: "恢复点列表加载失败，请稍后重试。", underlying: error)
        }
        isLoaded = true
    }

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

private struct RecoveryPointRestorePreviewView: View {
    let metadata: RecoveryPointMetadata
    let localBackupCoordinator: LocalBackupCoordinator

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter

    @State private var currentCounts: RecoveryPointCounts?
    @State private var isPreparingRestore = false
    @State private var showsConfirmation = false
    @State private var showsPreparedMessage = false

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "recoveryPointPreviewScrollView") {
            // swiftlint:disable trailing_comma
            TaskSurfaceSection(title: "将恢复的备份") {
                summaryBlock([
                    ("时间", BackupRestoreView.dateFormatter.string(from: metadata.createdAt)),
                    ("内容", metadata.counts.displayText),
                    ("原因", metadata.reason.displayText),
                    ("版本", "App \(metadata.appVersion)，Schema \(metadata.schemaVersion)"),
                ])
            }

            TaskSurfaceSection(title: "当前资料库") {
                summaryBlock([
                    ("当前内容", currentCounts?.displayText ?? "正在读取..."),
                    ("替换范围", "本机时刻、标签和照片"),
                    ("恢复方式", "下次启动前替换本机存储"),
                ])
            }
            // swiftlint:enable trailing_comma

            TaskSurfaceSection(title: "恢复说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("恢复会用此备份替换当前本机资料库。")
                        .font(AppTypography.body)
                        .foregroundStyle(theme.primaryText)
                    Text("确认后会先创建一个恢复前安全点，然后准备恢复。请完全退出并重新打开 App，恢复会在下次启动时完成。")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
            }

            Button {
                showsConfirmation = true
            } label: {
                Text(isPreparingRestore ? "正在准备恢复..." : "恢复此备份")
                    .font(AppTypography.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(TaskSurfaceMetrics.panelPadding)
                    .foregroundStyle(theme.onCommercialText)
                    .background(
                        RoundedRectangle(
                            cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                            style: .continuous
                        )
                        .fill(theme.commercialRed)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPreparingRestore)
            .accessibilityIdentifier("recoveryPointRestoreButton")
        }
        .settingsDetailNavigationChrome("恢复预览")
        .themedTaskContainer(theme)
        .task {
            await loadCurrentCounts()
        }
        .alert("恢复此备份？", isPresented: $showsConfirmation) {
            Button("恢复", role: .destructive) {
                prepareRestore()
            }
            .accessibilityIdentifier("recoveryPointRestoreConfirmButton")
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前本机资料库会在下次启动时被此备份替换。")
        }
        .alert("恢复已准备好", isPresented: $showsPreparedMessage) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("请完全退出并重新打开 App，恢复会在下次启动时完成。")
        }
        .userFacingErrorAlert(errorPresenter)
    }

    private func summaryBlock(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                TaskSurfaceRow {
                    Text(row.0).foregroundStyle(theme.secondaryText)
                } trailing: {
                    Text(row.1)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.trailing)
                }
                if index < rows.count - 1 {
                    TaskSurfaceSeparator()
                }
            }
        }
    }

    private func loadCurrentCounts() async {
        do {
            currentCounts = try await localBackupCoordinator.currentCounts()
        } catch {
            errorPresenter.report(message: "当前资料库摘要加载失败，请稍后重试。", underlying: error)
        }
    }

    private func prepareRestore() {
        guard !isPreparingRestore else { return }
        isPreparingRestore = true
        Task {
            do {
                try await localBackupCoordinator.prepareRestore(id: metadata.id)
                showsPreparedMessage = true
            } catch {
                errorPresenter.report(message: "准备恢复失败，请稍后重试。", underlying: error)
            }
            isPreparingRestore = false
        }
    }
}

private extension RecoveryPointMetadata {
    var summaryText: String {
        "\(counts.displayText) · \(reason.displayText) · App \(appVersion)"
    }
}

private extension RecoveryPointCounts {
    var displayText: String {
        "\(recordCount) 条记录，\(tagCount) 个标签，\(assetCount) 张照片"
    }
}

private extension RecoveryPointReason {
    var displayText: String {
        switch self {
        case .restoreSafety: "恢复前安全点"
        case .schemaMigration: "迁移前"
        case .stableChanges: "稳定变更"
        }
    }
}
