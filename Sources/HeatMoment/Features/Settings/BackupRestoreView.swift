import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    let backupPackageService: (any BackupPackageServicing)?

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(LocalBackupRestoreState.self) private var restoreState

    @State private var summary: BackupPackageLibrarySummary?
    @State private var exportResult: BackupPackageExportResult?
    @State private var importPreview: BackupPackagePreview?
    @State private var isLoadingSummary = false
    @State private var isExporting = false
    @State private var isInspectingImport = false
    @State private var isPreparingImport = false
    @State private var isFileImporterPresented = false
    @State private var showsImportConfirmation = false

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "backupRestoreScrollView") {
            summarySection
            fullBackupSection
            if let exportResult {
                exportResultSection(exportResult)
            }
            if let importPreview {
                importPreviewSection(importPreview)
            }
            safetySection
        }
        .appSheetDetailNavigationChrome("备份与恢复")
        .themedTaskContainer(theme)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.heatMomentBackupPackage]
        ) { result in
            handleImportedFile(result)
        }
        .alert("导入这份完整备份？", isPresented: $showsImportConfirmation) {
            Button("导入并替换", role: .destructive) {
                prepareImport()
            }
            .accessibilityIdentifier("backupPackageImportConfirmButton")
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前资料库会在下次启动时被这份备份完整替换。App 会先保存一份恢复前安全点。")
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
            await loadSummary()
        }
        .userFacingErrorAlert(errorPresenter)
    }

    private var summarySection: some View {
        TaskSurfaceSection(title: "当前资料库", accessibilityIdentifier: "backupSummarySection") {
            VStack(spacing: 0) {
                summaryRow(
                    title: "内容",
                    value: summary?.counts.displayText ?? (isLoadingSummary ? "正在读取..." : "不可用")
                )
                TaskSurfaceSeparator()
                summaryRow(
                    title: "上次导出完整备份",
                    value: summary?.lastExportedAt.map(Self.dateFormatter.string(from:)) ?? "暂无记录"
                )
            }
        }
    }

    private var fullBackupSection: some View {
        TaskSurfaceSection(title: "完整备份包", accessibilityIdentifier: "backupPackageSection") {
            VStack(alignment: .leading, spacing: 12) {
                Text("完整备份包包含资料库和照片，可用于重装 App 或换设备后的恢复。Markdown 和 PDF 只是阅读副本，不能导回恢复。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("backupPackageExplanationText")

                HStack(spacing: 12) {
                    actionButton(
                        title: isExporting ? "正在导出..." : "导出完整备份",
                        systemImage: "square.and.arrow.up",
                        isDisabled: backupPackageService == nil || isExporting || isInspectingImport
                    ) {
                        exportPackage()
                    }
                    actionButton(
                        title: isInspectingImport ? "正在读取..." : "导入完整备份",
                        systemImage: "square.and.arrow.down",
                        isDisabled: backupPackageService == nil || isExporting || isInspectingImport
                    ) {
                        isFileImporterPresented = true
                    }
                }
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private func exportResultSection(_ result: BackupPackageExportResult) -> some View {
        TaskSurfaceSection(title: "已生成备份包", accessibilityIdentifier: "backupExportResultSection") {
            VStack(spacing: 0) {
                summaryRow(title: "时间", value: Self.dateFormatter.string(from: result.createdAt))
                TaskSurfaceSeparator()
                summaryRow(title: "内容", value: result.counts.displayText)
                TaskSurfaceSeparator()
                summaryRow(title: "大小", value: ByteCountFormatter.string(fromByteCount: result.byteCount))
                TaskSurfaceSeparator()
                ShareLink(item: result.fileURL) {
                    TaskSurfaceRow {
                        Label("保存或分享备份包", systemImage: "square.and.arrow.up")
                            .foregroundStyle(theme.accent)
                    } trailing: {
                        TaskDisclosureIndicator()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backupPackageShareLink")
            }
        }
    }

    private func importPreviewSection(_ preview: BackupPackagePreview) -> some View {
        TaskSurfaceSection(title: "待导入备份", accessibilityIdentifier: "backupImportPreviewSection") {
            VStack(spacing: 0) {
                summaryRow(title: "备份时间", value: Self.dateFormatter.string(from: preview.createdAt))
                TaskSurfaceSeparator()
                summaryRow(title: "内容", value: preview.counts.displayText)
                TaskSurfaceSeparator()
                summaryRow(title: "来源版本", value: preview.sourceAppVersion)
                TaskSurfaceSeparator()
                summaryRow(title: "数据版本", value: "\(preview.sourceSchemaVersion)")
                TaskSurfaceSeparator()
                Button {
                    showsImportConfirmation = true
                } label: {
                    TaskSurfaceRow {
                        Label(
                            isPreparingImport ? "正在准备导入..." : "导入并替换当前资料库",
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

    private var safetySection: some View {
        TaskSurfaceSection(title: "恢复机制", accessibilityIdentifier: "backupSafetySection") {
            Text("导入完整备份前，App 会先创建一份恢复前安全点；真正替换会在下次启动时完成，避免运行中直接改写资料库。")
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
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

    private func actionButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(AppTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .foregroundStyle(theme.onAccentText)
                .background(
                    RoundedRectangle(
                        cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                        style: .continuous
                    )
                    .fill(isDisabled ? theme.accentDisabledFill : theme.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                let result = try await backupPackageService.exportPackage()
                exportResult = result
                summary = BackupPackageLibrarySummary(
                    counts: result.counts,
                    lastExportedAt: result.createdAt
                )
            } catch {
                errorPresenter.report(message: "完整备份导出失败，请重试。", underlying: error)
            }
        }
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

private extension BackupRecoveryCounts {
    var displayText: String {
        "\(recordCount) 条记录，已用标签 \(usedTagCount) 个，\(assetCount) 张照片"
    }
}

private extension ByteCountFormatter {
    static func string(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
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
