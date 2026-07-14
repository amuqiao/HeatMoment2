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
    @State private var isExporting = false
    @State private var isShareSheetPresented = false
    @State private var isResolvingExportShare = false
    @State private var isInspectingImport = false
    @State private var isPreparingImport = false
    @State private var isFileImporterPresented = false
    @State private var showsImportConfirmation = false
    @State private var selectedOperation: BackupPackageOperation = .export

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "backupRestoreScrollView") {
            summarySection
            fullBackupSection
            if selectedOperation == .import, let importPreview {
                importPreviewSection(importPreview)
            }
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
            onDismiss: {
                resolvePreparedExport(completed: false)
            },
            content: {
                if let preparedExport {
                    BackupPackageShareSheet(fileURL: preparedExport.fileURL) { completed in
                        resolvePreparedExport(completed: completed)
                    }
                }
            }
        )
        .alert("导入这份完整备份？", isPresented: $showsImportConfirmation) {
            Button("导入并替换", role: .destructive) {
                prepareImport()
            }
            .accessibilityIdentifier("backupPackageImportConfirmButton")
            Button("取消", role: .cancel) {}
        } message: {
            Text("导入后会替换当前内容。开始前会自动保护现有资料。")
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
            await cleanupAbandonedPreparedExports()
            await loadSummary()
        }
        .userFacingErrorAlert(errorPresenter)
    }

    private var summarySection: some View {
        TaskSurfaceSection(title: "当前内容", accessibilityIdentifier: "backupSummarySection") {
            VStack(spacing: 0) {
                summaryRow(
                    title: "内容",
                    value: summary?.counts.displayText ?? (isLoadingSummary ? "正在读取..." : "不可用")
                )
                TaskSurfaceSeparator()
                summaryRow(
                    title: "上次备份",
                    value: summary?.lastExportedAt.map(Self.dateFormatter.string(from:)) ?? "从未备份"
                )
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

    private func importPreviewSection(_ preview: BackupPackagePreview) -> some View {
        TaskSurfaceSection(title: "将要导入", accessibilityIdentifier: "backupImportPreviewSection") {
            VStack(spacing: 0) {
                summaryRow(title: "备份时间", value: Self.dateFormatter.string(from: preview.createdAt))
                TaskSurfaceSeparator()
                summaryRow(title: "内容", value: preview.counts.displayText)
                TaskSurfaceSeparator()
                Button {
                    showsImportConfirmation = true
                } label: {
                    TaskSurfaceRow {
                        Label(
                            isPreparingImport ? "正在准备导入..." : "导入并替换",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .foregroundStyle(theme.commercialRed)
                    } trailing: {
                        TaskDisclosureIndicator()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPreparingImport)
                .accessibilityIdentifier("backupPackagePrepareImportButton")
            }
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
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

    private func cleanupAbandonedPreparedExports() async {
        guard let backupPackageService else { return }
        do {
            try await backupPackageService.discardAbandonedPreparedExports()
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
        } catch {
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
                    summary = BackupPackageLibrarySummary(
                        counts: preparedExport.counts,
                        lastExportedAt: completion.exportedAt
                    )
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
            message: "备份已导出，但临时文件清理失败。下次进入页面会重试清理。",
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

    private func prepareImport() {
        guard let backupPackageService, let importPreview, !isPreparingImport else { return }
        isPreparingImport = true
        Task { @MainActor in
            defer { isPreparingImport = false }
            do {
                let prepared = try await backupPackageService.prepareImport(importPreview)
                restoreState.markPendingRestoreArmed(context: prepared.pendingContext)
            } catch {
                errorPresenter.report(message: "准备导入失败，请重试。", underlying: error)
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
