import Foundation

extension ExportView {
    struct FailureState: Equatable {
        let attemptID: Int
        let message: String
        let retryAction: FailureRetryAction
    }

    enum FailureRetryAction: Equatable {
        case export
        case loadDateBounds
    }

    enum ScopeMode: String, CaseIterable {
        case all
        case dateRange

        var displayName: String {
            switch self {
            case .all:
                return "全部"
            case .dateRange:
                return "日期范围"
            }
        }
    }

    #if DEBUG
        struct DateBoundsLoadError: Error {}

        struct FailingPDFExportSnapshotProvider: ExportSnapshotProviding {
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
                            assets: request.includePhotos
                                ? [
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
                                : []
                        )
                    ]
                )
            }
        }
    #endif
}
