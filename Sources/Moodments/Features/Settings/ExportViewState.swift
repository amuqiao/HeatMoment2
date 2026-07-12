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

    #if DEBUG
        struct DateBoundsLoadError: Error {}
    #endif
}
