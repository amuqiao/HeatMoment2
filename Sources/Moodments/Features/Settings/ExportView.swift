import SwiftUI

struct ExportView: View {
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(ThemeManager.self) private var theme

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var exportResult: ExportResult?
    @State private var exportFailure: ExportFailureState?
    @State private var isExporting = false
    @State private var exportAttemptID = 0
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "exportScrollView") {
            summarySection
            formatSection
            generateButton
            if let exportResult {
                resultSection(exportResult)
            }
            if let exportFailure {
                failureSection(exportFailure)
            }
        }
        .settingsDetailNavigationChrome("导出")
        .themedTaskContainer(theme)
        .onChange(of: selectedFormat) { _, _ in
            exportResult = nil
            exportFailure = nil
        }
        .onDisappear {
            cancelExport()
        }
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "exportSummarySection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("导出会生成副本，不会改变当前数据，也不会影响 iCloud 同步。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("exportReadonlyText")
                Text("当前支持 Markdown 和 PDF；Markdown 会保留相对照片目录，PDF 会把照片嵌入文档。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("exportScopeText")
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var formatSection: some View {
        TaskSurfaceSection(title: "格式", accessibilityIdentifier: "exportFormatSection") {
            Picker("导出格式", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
            .disabled(isExporting)
            .accessibilityIdentifier("exportFormatPicker")
        }
    }

    private var generateButton: some View {
        Button {
            exportSelectedFormat()
        } label: {
            Label {
                Text(isExporting ? selectedFormat.exportingTitle : selectedFormat.generateTitle)
            } icon: {
                Image(systemName: selectedFormat.systemImage)
            }
            .font(AppTypography.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(TaskSurfaceMetrics.panelPadding)
            .foregroundStyle(theme.onAccentText)
            .background(
                RoundedRectangle(
                    cornerRadius: TaskSurfaceMetrics.panelCornerRadius,
                    style: .continuous
                )
                .fill(isExporting ? theme.accentDisabledFill : theme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
        .accessibilityIdentifier("exportGenerateButton")
    }

    private func resultSection(_ result: ExportResult) -> some View {
        TaskSurfaceSection(title: "导出结果", accessibilityIdentifier: "exportSuccessState") {
            VStack(spacing: 0) {
                TaskSurfaceRow {
                    Text("格式").foregroundStyle(theme.secondaryText)
                } trailing: {
                    Text(result.format.displayName)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.primaryText)
                        .accessibilityIdentifier("exportResultFormatText")
                }
                TaskSurfaceSeparator()
                TaskSurfaceRow {
                    Text("文件").foregroundStyle(theme.secondaryText)
                } trailing: {
                    Text(result.fileName)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("exportFileNameText")
                }
                TaskSurfaceSeparator()
                TaskSurfaceRow {
                    Text("内容").foregroundStyle(theme.secondaryText)
                } trailing: {
                    Text("\(result.momentCount) 条时刻，\(result.assetCount) 张照片")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("exportAssetsSummaryText")
                }
                TaskSurfaceSeparator()
                ShareLink(item: shareURL(for: result)) {
                    TaskSurfaceRow {
                        Label(result.format.shareTitle, systemImage: "square.and.arrow.up")
                            .foregroundStyle(theme.primaryText)
                    } trailing: {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("exportShareLink")
            }
        }
    }

    private func failureSection(_ failure: ExportFailureState) -> some View {
        TaskSurfaceSection(title: "导出失败", accessibilityIdentifier: "exportFailureState") {
            VStack(alignment: .leading, spacing: 12) {
                Text(failure.message)
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("exportFailureMessage")
                Button {
                    exportSelectedFormat()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(AppTypography.body.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
                .accessibilityIdentifier("exportRetryButton")
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
        .accessibilityValue("\(failure.attemptID)")
    }

    private func exportSelectedFormat() {
        guard !isExporting else { return }
        exportTask?.cancel()
        isExporting = true
        exportResult = nil
        exportFailure = nil
        exportAttemptID += 1
        let attemptID = exportAttemptID
        let format = selectedFormat
        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let service = makeExportService(format: format)
                exportResult = try await service.exportAll(format: format)
            } catch is CancellationError {
                exportResult = nil
            } catch {
                exportFailure = ExportFailureState(
                    attemptID: attemptID,
                    message: "\(format.displayName) 导出失败，请重试。"
                )
            }
        }
    }

    private func makeExportService(format: ExportFormat) -> ExportService {
        #if DEBUG
            if format == .pdf, UITestSupport.wantsExportForcePDFFailure {
                return ExportService(snapshotProvider: FailingPDFExportSnapshotProvider())
            }
        #endif
        return ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(
                repository: canonicalService.repository
            )
        )
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
    }

    private func shareURL(for result: ExportResult) -> URL {
        switch result.format {
        case .markdown:
            return result.packageDirectoryURL
        case .pdf:
            return result.fileURL
        }
    }
}

private struct ExportFailureState: Equatable {
    let attemptID: Int
    let message: String
}

#if DEBUG
    private struct FailingPDFExportSnapshotProvider: ExportSnapshotProviding {
        func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot {
            ExportSnapshot(
                exportedAt: request.requestedAt,
                scope: request.scope,
                includePhotos: request.includePhotos,
                moments: [
                    ExportMoment(
                        id: UUID(
                            uuid: (
                                0x11, 0x11, 0x11, 0x11,
                                0x11, 0x11,
                                0x11, 0x11,
                                0x11, 0x11,
                                0x11, 0x11, 0x11, 0x11, 0x11, 0x11
                            )
                        ),
                        title: "坏图导出测试",
                        bodyText: "用于验证 PDF 导出失败态和重试入口。",
                        occurredAt: Date(timeIntervalSince1970: 3_600),
                        mood: .normal,
                        tagNames: [],
                        assets: [
                            ExportAsset(
                                id: UUID(
                                    uuid: (
                                        0x22, 0x22, 0x22, 0x22,
                                        0x22, 0x22,
                                        0x22, 0x22,
                                        0x22, 0x22,
                                        0x22, 0x22, 0x22, 0x22, 0x22, 0x22
                                    )
                                ),
                                data: Data([0x00, 0x01])
                            )
                        ]
                    )
                ]
            )
        }
    }
#endif

#Preview {
    ExportView()
        .environment(ThemeManager())
        .environment(CanonicalLibraryService.makeInMemoryForPreview())
}
