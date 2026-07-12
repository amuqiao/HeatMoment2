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
    #endif
}
