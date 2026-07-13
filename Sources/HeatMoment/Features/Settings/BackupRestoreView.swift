import SwiftUI

struct BackupRestoreView: View {
    let backupRestoreService: (any BackupRestoreServicing)?

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter

    @State private var recoveryPoints: [BackupRecoveryPoint] = []
    @State private var isLoaded = false

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "backupRestoreScrollView") {
            summarySection
            if let backupRestoreService {
                recoveryPointList(backupRestoreService)
            } else {
                unavailableSection
            }
        }
        .appSheetDetailNavigationChrome("备份与恢复")
        .themedTaskContainer(theme)
        .task {
            await reload()
        }
        .userFacingErrorAlert(errorPresenter)
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "backupRestoreSummarySection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("自动备份")
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Text("App 会自动保留最近 3 份本机备份。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("backupRestoreRetentionText")
                Text("当你误删或误改内容时，可以恢复到之前的状态。备份由 App 自动维护，不能手动删除。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("backupRestoreSystemManagedText")
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var unavailableSection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "backupRestoreUnavailableSection") {
            Text("当前模式下未启用本机自动备份。")
                .font(AppTypography.body)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
                .accessibilityIdentifier("backupRestoreUnavailableState")
        }
    }

    private func recoveryPointList(
        _ backupRestoreService: any BackupRestoreServicing
    ) -> some View {
        TaskSurfaceSection(title: "最近备份", accessibilityIdentifier: "recoveryPointsSection") {
            if isLoaded && recoveryPoints.isEmpty {
                Text("暂无可用备份")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("recoveryPointsEmptyState")
            } else {
                ForEach(Array(recoveryPoints.enumerated()), id: \.element.id) { index, metadata in
                    recoveryPointRow(metadata, service: backupRestoreService)
                    if index < recoveryPoints.count - 1 {
                        TaskSurfaceSeparator()
                    }
                }
            }
        }
    }

    private func recoveryPointRow(
        _ metadata: BackupRecoveryPoint,
        service: any BackupRestoreServicing
    ) -> some View {
        NavigationLink {
            RecoveryPointRestorePreviewView(
                metadata: metadata,
                backupRestoreService: service
            )
        } label: {
            TaskSurfaceRow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(Self.dateFormatter.string(from: metadata.createdAt))
                            .font(AppTypography.body)
                            .foregroundStyle(theme.primaryText)
                            .accessibilityIdentifier("recoveryPointCreatedAtText")
                        if metadata.status == .invalid {
                            Text("备份不可用")
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
                        .accessibilityIdentifier("recoveryPointSummaryText")
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
        guard let backupRestoreService else {
            isLoaded = true
            return
        }
        do {
            recoveryPoints = try await backupRestoreService.listRecoveryPoints()
        } catch {
            errorPresenter.report(message: "备份列表加载失败，请稍后重试。", underlying: error)
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
    let metadata: BackupRecoveryPoint
    let backupRestoreService: any BackupRestoreServicing

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(LocalBackupRestoreState.self) private var restoreState

    @State private var currentCounts: BackupRecoveryCounts?
    @State private var isPreparingRestore = false
    @State private var showsConfirmation = false

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "recoveryPointPreviewScrollView") {
            // swiftlint:disable trailing_comma
            TaskSurfaceSection(title: "备份内容") {
                summaryBlock([
                    ("时间", BackupRestoreView.dateFormatter.string(from: metadata.createdAt)),
                    ("内容", metadata.counts.displayText),
                ])
            }

            TaskSurfaceSection(title: "当前内容") {
                summaryBlock([
                    ("当前内容", currentCounts?.displayText ?? "正在读取..."),
                ])
            }
            // swiftlint:enable trailing_comma

            TaskSurfaceSection(title: "恢复说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("恢复后，当前本机内容会替换为这份备份。")
                        .font(AppTypography.body)
                        .foregroundStyle(theme.primaryText)
                        .accessibilityIdentifier("recoveryPointRestoreReplaceWarning")
                    Text("App 会先保存一份恢复前备份，方便你撤回。请完全退出并重新打开 App，恢复会在下次启动时完成。")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.secondaryText)
                        .accessibilityIdentifier("recoveryPointRestoreRestartInstruction")
                }
                .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
            }

            Button {
                showsConfirmation = true
            } label: {
                Text(isPreparingRestore ? "正在准备恢复..." : "恢复到这份备份")
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
        .appSheetDetailNavigationChrome("恢复备份")
        .themedTaskContainer(theme)
        .task {
            await loadCurrentCounts()
        }
        .alert("恢复到这份备份？", isPresented: $showsConfirmation) {
            Button("恢复", role: .destructive) {
                prepareRestore()
            }
            .accessibilityIdentifier("recoveryPointRestoreConfirmButton")
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前本机内容会被替换。App 会先保存一份恢复前备份，方便你撤回。")
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { restoreState.isPendingRestoreArmed },
                set: { _ in }
            )
        ) {
            PendingLocalRestoreView(context: restoreState.pendingContext)
                .interactiveDismissDisabled()
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
            currentCounts = try await backupRestoreService.currentCounts()
        } catch {
            errorPresenter.report(message: "当前内容摘要加载失败，请稍后重试。", underlying: error)
        }
    }

    private func prepareRestore() {
        guard !isPreparingRestore else { return }
        isPreparingRestore = true
        Task { @MainActor in
            do {
                let context = try await backupRestoreService.prepareRestore(id: metadata.id)
                restoreState.markPendingRestoreArmed(context: context)
            } catch {
                errorPresenter.report(message: "准备恢复失败，请稍后重试。", underlying: error)
            }
            isPreparingRestore = false
        }
    }
}

private extension BackupRecoveryPoint {
    var summaryText: String {
        counts.displayText
    }
}

private extension BackupRecoveryCounts {
    var displayText: String {
        "\(recordCount) 条记录，已用标签 \(usedTagCount) 个，\(assetCount) 张照片"
    }
}
