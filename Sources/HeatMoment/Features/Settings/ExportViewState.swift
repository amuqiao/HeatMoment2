import Foundation

enum ExportDateRangeDefaults {
    static func recentThreeDays(
        containing date: Date = .now,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -2, to: end) else {
            preconditionFailure("Calendar failed to build recent export date range.")
        }
        return (start, end)
    }
}

extension ExportView {
    struct FailureState: Equatable {
        let attemptID: Int
        let message: String
        let retryAction: FailureRetryAction
    }

    enum FailureRetryAction: Equatable {
        case export
        case cleanupTemporaryExports
        case loadDateBounds
        case share
    }

    #if DEBUG
        struct DateBoundsLoadError: Error {}
        struct ShareFailureError: Error {}
    #endif
}
