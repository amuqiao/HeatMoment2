import SwiftUI

extension ExportView {
    struct ResultSection: View {
        @Environment(ThemeManager.self) private var theme

        let result: ExportResult

        var body: some View {
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

        private func shareURL(for result: ExportResult) -> URL {
            switch result.format {
            case .markdown:
                return result.packageDirectoryURL
            case .pdf:
                return result.fileURL
            }
        }
    }

    struct FailureSection: View {
        @Environment(ThemeManager.self) private var theme

        let failure: FailureState
        let isExporting: Bool
        let retry: (FailureState) -> Void

        var body: some View {
            TaskSurfaceSection(title: "导出失败", accessibilityIdentifier: "exportFailureState") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(failure.message)
                        .font(AppTypography.body)
                        .foregroundStyle(theme.primaryText)
                        .accessibilityIdentifier("exportFailureMessage")
                    Button {
                        retry(failure)
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
    }
}
