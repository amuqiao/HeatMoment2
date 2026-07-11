import SwiftData
import SwiftUI

struct MarkdownExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter

    @State private var exportResult: MarkdownExportResult?
    @State private var isExporting = false

    var body: some View {
        TaskPageScrollView(accessibilityIdentifier: "markdownExportScrollView") {
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
    }

    private var summarySection: some View {
        TaskSurfaceSection(accessibilityIdentifier: "markdownExportSummarySection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("导出会生成副本，不会改变当前数据，也不会影响 iCloud 同步。")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("markdownExportReadonlyText")
                Text("当前阶段支持 Markdown；照片会复制到相邻 assets 目录，并在文档中使用相对链接。")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityIdentifier("markdownExportScopeText")
            }
            .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
    }

    private var formatSection: some View {
        TaskSurfaceSection(title: "格式", accessibilityIdentifier: "markdownExportFormatSection") {
            TaskSurfaceRow {
                Label("Markdown", systemImage: "doc.plaintext")
                    .foregroundStyle(theme.primaryText)
            } trailing: {
                Text("已选择")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("markdownExportFormatMarkdownRow")
        }
    }

    private var generateButton: some View {
        Button {
            exportMarkdown()
        } label: {
            Text(isExporting ? "正在生成..." : "生成 Markdown")
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
        .accessibilityIdentifier("markdownExportGenerateButton")
    }

    private func resultSection(_ result: MarkdownExportResult) -> some View {
        TaskSurfaceSection(title: "导出结果", accessibilityIdentifier: "markdownExportSuccessState") {
            VStack(spacing: 0) {
                TaskSurfaceRow {
                    Text("文件").foregroundStyle(theme.secondaryText)
                } trailing: {
                    Text(result.fileName)
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("markdownExportFileNameText")
                }
                TaskSurfaceSeparator()
                TaskSurfaceRow {
                    Text("内容").foregroundStyle(theme.secondaryText)
                } trailing: {
                    Text("\(result.momentCount) 条时刻，\(result.assetCount) 张照片")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("markdownExportAssetsSummaryText")
                }
                TaskSurfaceSeparator()
                ShareLink(item: result.packageDirectoryURL) {
                    TaskSurfaceRow {
                        Label("分享导出目录", systemImage: "square.and.arrow.up")
                            .foregroundStyle(theme.primaryText)
                    } trailing: {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("markdownExportShareLink")
            }
        }
    }

    private func exportMarkdown() {
        guard !isExporting else { return }
        isExporting = true
        exportResult = nil
        Task {
            do {
                let service = MarkdownExportService(modelContainer: modelContext.container)
                exportResult = try await service.exportAll()
            } catch {
                errorPresenter.report(message: "Markdown 导出失败，请稍后重试。", underlying: error)
            }
            isExporting = false
        }
    }
}

#Preview {
    MarkdownExportView()
        .environment(ThemeManager())
        .environment(ErrorPresenter())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
