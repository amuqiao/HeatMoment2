import SwiftData
import SwiftUI

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var exportResult: ExportResult?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "exportScrollView") {
            summarySection
            formatSection
            generateButton
            if let exportResult {
                resultSection(exportResult)
            }
        }
        .settingsDetailNavigationChrome("导出")
        .themedTaskContainer(theme)
        .userFacingErrorAlert(errorPresenter)
        .onChange(of: selectedFormat) { _, _ in
            exportResult = nil
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

    private func exportSelectedFormat() {
        guard !isExporting else { return }
        exportTask?.cancel()
        isExporting = true
        exportResult = nil
        let format = selectedFormat
        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let service = ExportService(modelContainer: modelContext.container)
                exportResult = try await service.exportAll(format: format)
            } catch is CancellationError {
                exportResult = nil
            } catch {
                errorPresenter.report(
                    message: "\(format.displayName) 导出失败，请稍后重试。",
                    underlying: error
                )
            }
        }
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

#Preview {
    ExportView()
        .environment(ThemeManager())
        .environment(ErrorPresenter())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
