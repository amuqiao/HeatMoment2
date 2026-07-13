import SwiftUI
import UIKit

extension ExportView {
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

    struct ExportShareSheet: UIViewControllerRepresentable {
        let transaction: ExportShareTransaction
        let onComplete: (Bool, Error?) -> Void

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(
                activityItems: [shareURL(for: transaction)],
                applicationActivities: nil
            )
            controller.popoverPresentationController?.sourceView = controller.view
            controller.completionWithItemsHandler = { _, completed, _, error in
                Task { @MainActor in
                    onComplete(completed, error)
                }
            }
            return controller
        }

        func updateUIViewController(
            _ uiViewController: UIActivityViewController,
            context: Context
        ) {
        }

        private func shareURL(for transaction: ExportShareTransaction) -> URL {
            switch transaction.format {
            case .markdown:
                return transaction.packageDirectoryURL
            case .pdf:
                return transaction.fileURL
            }
        }
    }
}
