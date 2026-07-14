import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    let backupPackageService: (any BackupPackageServicing)?

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(LocalBackupRestoreState.self) private var restoreState

    @State private var summary: BackupPackageLibrarySummary?
    @State private var preparedExport: BackupPackagePreparedExport?
    @State private var importPreview: BackupPackagePreview?
    @State private var isLoadingSummary = false
    @State private var hasSummaryLoadFailed = false
    @State private var isExporting = false
    @State private var isShareSheetPresented = false
    @State private var isResolvingExportShare = false
    @State private var isInspectingImport = false
    @State private var isPreparingImport = false
    @State private var isFileImporterPresented = false
    @State private var selectedOperation: BackupPackageOperation = .export

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "backupRestoreScrollView") {
            summarySection
            fullBackupSection
            primaryActionButton
        }
        .appSheetDetailNavigationChrome("备份/还原")
        .themedTaskContainer(theme)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.heatMomentBackupPackage]
        ) { result in
            handleImportedFile(result)
        }
        .sheet(
            isPresented: $isShareSheetPresented,
            content: {
                if let preparedExport {
                    BackupPackageShareSheet(fileURL: preparedExport.fileURL) { completed in
                        resolvePreparedExport(completed: completed)
                    }
                }
            }
        )
        .sheet(isPresented: importConfirmationBinding) {
            if let importPreview {
                BackupImportConfirmationSheet(
                    preview: importPreview,
                    isPreparingImport: isPreparingImport,
                    onCancel: { cancelImportConfirmation() },
                    onConfirm: { prepareImport(importPreview) }
                )
                .interactiveDismissDisabled(isPreparingImport)
            }
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
        .task {
            await cleanupAbandonedBackupWorkspaces()
            await loadSummary()
        }
        .userFacingErrorAlert(errorPresenter)
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "backupSummarySection") {
            VStack(alignment: .leading, spacing: 16) {
                if let currentSnapshot = summary?.currentSnapshot {
                    summarySnapshotBlock(
                        title: "当前内容",
                        counts: currentSnapshot.counts,
                        timestampLabel: "读取于",
                        timestamp: currentSnapshot.readAt,
                        accessibilityPrefix: "backupCurrentSummary"
                    )
                } else {
                    summaryPlaceholderBlock(
                        title: "当前内容",
                        message: summaryPlaceholderMessage,
                        accessibilityPrefix: "backupCurrentSummary"
                    )
                }

                summarySeparator

                if let lastExportSnapshot = summary?.lastExportSnapshot {
                    summarySnapshotBlock(
                        title: "上次导出",
                        counts: lastExportSnapshot.counts,
                        timestampLabel: "导出于",
                        timestamp: lastExportSnapshot.exportedAt,
                        accessibilityPrefix: "backupLastExportSummary"
                    )
                } else {
                    summaryPlaceholderBlock(
                        title: "上次导出",
                        message: summary == nil ? summaryPlaceholderMessage : "从未导出",
                        accessibilityPrefix: "backupLastExportSummary"
                    )
                }
            }
        }
    }

    private var fullBackupSection: some View {
        TaskSurfaceSection(title: "完整备份", accessibilityIdentifier: "backupPackageSection") {
            Picker("操作方式", selection: $selectedOperation) {
                ForEach(BackupPackageOperation.allCases, id: \.self) { operation in
                    Text(operation.displayName).tag(operation)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
            .disabled(isPrimaryActionDisabled)
            .accessibilityIdentifier("backupPackageOperationPicker")
        }
    }

    private func summarySnapshotBlock(
        title: String,
        counts: BackupRecoveryCounts,
        timestampLabel: String,
        timestamp: Date,
        accessibilityPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.body.weight(.semibold))
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 8) {
                summaryMetric(
                    title: "记录",
                    value: counts.recordCount,
                    accessibilityIdentifier: "\(accessibilityPrefix)RecordMetric"
                )
                summaryMetric(
                    title: "使用标签",
                    value: counts.usedTagCount,
                    accessibilityIdentifier: "\(accessibilityPrefix)UsedTagMetric"
                )
                summaryMetric(
                    title: "照片",
                    value: counts.assetCount,
                    accessibilityIdentifier: "\(accessibilityPrefix)PhotoMetric"
                )
            }

            Text("\(timestampLabel) \(Self.dateFormatter.string(from: timestamp))")
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("\(accessibilityPrefix)Timestamp")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryMetric(
        title: String,
        value: Int,
        accessibilityIdentifier: String
    ) -> some View {
        Text("\(title) \(value)")
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .accessibilityIdentifier(accessibilityIdentifier)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryPlaceholderBlock(
        title: String,
        message: String,
        accessibilityPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.body.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
                .accessibilityIdentifier("\(accessibilityPrefix)Placeholder")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summarySeparator: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: 1 / UIScreen.main.scale)
            .frame(maxWidth: .infinity)
    }

    private var summaryPlaceholderMessage: String {
        if isLoadingSummary { return "正在读取..." }
        if hasSummaryLoadFailed { return "不可用" }
        return "不可用"
    }

    private func cleanupAbandonedBackupWorkspaces() async {
        guard let backupPackageService else { return }
        do {
            try await backupPackageService.discardAbandonedPreparedExports()
            try await backupPackageService.discardAllImportStaging()
        } catch {
            errorPresenter.report(message: "备份临时文件清理失败，请稍后重试。", underlying: error)
        }
    }

    private func loadSummary() async {
        guard let backupPackageService, !isLoadingSummary else { return }
        isLoadingSummary = true
        defer { isLoadingSummary = false }
        do {
            summary = try await backupPackageService.currentSummary()
            hasSummaryLoadFailed = false
        } catch {
            summary = nil
            hasSummaryLoadFailed = true
            errorPresenter.report(message: "备份摘要读取失败，请稍后重试。", underlying: error)
        }
    }

    private func exportPackage() {
        guard let backupPackageService, !isExporting else { return }
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                preparedExport = try await backupPackageService.prepareExportPackage()
                #if DEBUG
                    if UITestSupport.wantsBackupPackageShareAutoComplete {
                        resolvePreparedExport(completed: true)
                        return
                    }
                #endif
                isShareSheetPresented = true
            } catch {
                errorPresenter.report(message: "备份导出失败，请重试。", underlying: error)
            }
        }
    }

    private func resolvePreparedExport(completed: Bool) {
        guard !isResolvingExportShare, let preparedExport, let backupPackageService else { return }
        isResolvingExportShare = true
        isShareSheetPresented = false

        Task { @MainActor in
            defer {
                self.preparedExport = nil
                isResolvingExportShare = false
            }
            do {
                if completed {
                    let completion =
                        try await backupPackageService.completePreparedExport(preparedExport)
                    summary = try await backupPackageService.currentSummary()
                    reportPreparedExportCleanupIfNeeded(completion.cleanupStatus)
                } else {
                    try await backupPackageService.discardPreparedExport(preparedExport)
                }
            } catch {
                errorPresenter.report(message: "备份导出失败，请重试。", underlying: error)
            }
        }
    }

    private func reportPreparedExportCleanupIfNeeded(
        _ cleanupStatus: BackupPackagePreparedExportCleanupStatus
    ) {
        guard case let .failedAfterExportRecorded(details) = cleanupStatus else { return }
        errorPresenter.report(
            message: "备份已导出，但临时文件收尾失败。下次进入页面会重试处理。",
            underlying: BackupPackagePreparedExportCleanupError.failed(details)
        )
    }

    private func handleImportedFile(_ result: Result<URL, Error>) {
        guard let backupPackageService, !isInspectingImport else { return }
        isInspectingImport = true
        importPreview = nil
        Task { @MainActor in
            defer { isInspectingImport = false }
            do {
                let url = try result.get()
                importPreview = try await backupPackageService.inspectPackage(at: url)
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                    return
                }
                errorPresenter.report(message: "备份包读取或校验失败，请选择有效的完整备份包。", underlying: error)
            }
        }
    }

    private func prepareImport(_ preview: BackupPackagePreview) {
        guard let backupPackageService, !isPreparingImport else { return }
        isPreparingImport = true
        Task { @MainActor in
            defer { isPreparingImport = false }
            do {
                let prepared = try await backupPackageService.prepareImport(preview)
                importPreview = nil
                restoreState.markPendingRestoreArmed(context: prepared.pendingContext)
            } catch {
                errorPresenter.report(message: "准备导入失败，请重试。", underlying: error)
                importPreview = nil
                discardImportPreview(preview)
            }
        }
    }

    private var importConfirmationBinding: Binding<Bool> {
        Binding(
            get: { importPreview != nil },
            set: { isPresented in
                guard !isPresented else { return }
                cancelImportConfirmation()
            }
        )
    }

    private func cancelImportConfirmation() {
        guard !isPreparingImport else { return }
        guard let preview = importPreview else { return }
        importPreview = nil
        discardImportPreview(preview)
    }

    private func discardImportPreview(_ preview: BackupPackagePreview) {
        guard let backupPackageService else { return }
        Task { @MainActor in
            do {
                try await backupPackageService.discardImportPreview(preview)
            } catch {
                errorPresenter.report(message: "备份临时文件清理失败，请稍后重试。", underlying: error)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

private extension BackupRestoreView {
    var primaryActionButton: some View {
        Button {
            performSelectedOperation()
        } label: {
            Label(primaryActionTitle, systemImage: primaryActionSystemImage)
                .font(AppTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(TaskSurfaceMetrics.panelPadding)
                .foregroundStyle(theme.onAccentText)
                .background(
                    RoundedRectangle(
                        cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                        style: .continuous
                    )
                    .fill(isPrimaryActionDisabled ? theme.accentDisabledFill : theme.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(isPrimaryActionDisabled)
        .accessibilityIdentifier("backupPackagePrimaryButton")
    }

    var isPrimaryActionDisabled: Bool {
        backupPackageService == nil
            || isExporting
            || isShareSheetPresented
            || isResolvingExportShare
            || isInspectingImport
            || isPreparingImport
            || importPreview != nil
    }

    var primaryActionTitle: String {
        switch selectedOperation {
        case .export:
            if isExporting { return "正在准备备份..." }
            if isShareSheetPresented || isResolvingExportShare { return "正在分享..." }
            return "导出备份"
        case .import:
            return isInspectingImport ? "正在读取备份..." : "导入备份"
        }
    }

    var primaryActionSystemImage: String {
        switch selectedOperation {
        case .export:
            return "square.and.arrow.up"
        case .import:
            return "square.and.arrow.down"
        }
    }

    func performSelectedOperation() {
        switch selectedOperation {
        case .export:
            exportPackage()
        case .import:
            isFileImporterPresented = true
        }
    }
}

private enum BackupPackagePreparedExportCleanupError: Error {
    case failed(String)
}

private enum BackupPackageOperation: CaseIterable, Hashable {
    case export
    case `import`

    var displayName: String {
        switch self {
        case .export:
            return "导出备份"
        case .import:
            return "导入还原"
        }
    }
}

private extension BackupRecoveryCounts {
    var displayText: String {
        "\(recordCount) 条记录，已用标签 \(usedTagCount) 个，\(assetCount) 张照片"
    }
}

private struct BackupImportConfirmationSheet: View {
    let preview: BackupPackagePreview
    let isPreparingImport: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        AppSheetScaffold {
            TaskPageScrollView(
                spacing: 16,
                contentInsets: EdgeInsets(top: 24, leading: 16, bottom: 40, trailing: 16),
                accessibilityIdentifier: "backupImportConfirmationSheet"
            ) {
                TaskSurfaceSection(accessibilityIdentifier: "backupImportConfirmationSection") {
                    VStack(spacing: 0) {
                        row(title: "备份时间", value: Self.dateFormatter.string(from: preview.createdAt))
                        TaskSurfaceSeparator()
                        row(title: "内容", value: preview.counts.displayText)
                    }
                }

                Text("还原后将替换当前所有数据。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.danger)
                    .padding(.horizontal, 2)
                    .accessibilityIdentifier("backupImportConfirmationWarningText")
            }
            .appSheetChrome(
                title: "还原备份",
                cancellation: AppSheetAction(
                    "取消",
                    accessibilityIdentifier: "backupPackageImportCancelButton",
                    isDisabled: isPreparingImport,
                    handler: onCancel
                ),
                confirmation: AppSheetAction(
                    isPreparingImport ? "正在准备..." : "还原",
                    accessibilityIdentifier: "backupPackageImportConfirmButton",
                    role: .destructive,
                    isDisabled: isPreparingImport,
                    isProminent: true,
                    handler: onConfirm
                )
            )
        }
        .presentationDetents([.medium])
    }

    private func row(title: String, value: String) -> some View {
        TaskSurfaceRow {
            Text(title)
                .foregroundStyle(theme.secondaryText)
        } trailing: {
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

private struct BackupPackageShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = controller.view
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in
                onComplete(completed)
            }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
    }
}

extension UTType {
    static let heatMomentBackupPackage = UTType(exportedAs: "app.heatmoment.backup-package")
}

#Preview {
    BackupRestoreView(backupPackageService: nil)
        .environment(ThemeManager())
        .environment(ErrorPresenter())
        .environment(LocalBackupRestoreState())
}
