import Foundation

actor CanonicalExportSnapshotStore: ExportSnapshotProviding {
    private let repository: CanonicalLibraryRepository
    private var calendar: Calendar

    init(repository: CanonicalLibraryRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot {
        let range = try normalizedRange(for: request.scope)
        let payloads = try await repository.exportPayload(
            startAtInclusive: range?.start,
            endAtExclusive: range?.end,
            includePhotos: request.includePhotos
        )
        var moments: [ExportMoment] = []
        moments.reserveCapacity(payloads.count)
        for payload in payloads {
            let assets = payload.imageDatas.map { ExportAsset(id: $0.id, data: $0.data) }
            let moment = ExportMoment(
                id: payload.record.id,
                title: payload.record.title,
                bodyText: payload.record.bodyText,
                occurredAt: payload.record.occurredAt,
                mood: payload.record.mood,
                tagNames: payload.tagNames,
                assets: assets
            )
            moments.append(moment)
        }
        return ExportSnapshot(
            exportedAt: request.requestedAt,
            scope: request.scope,
            includePhotos: request.includePhotos,
            moments: moments
        )
    }

    private func normalizedRange(for scope: ExportScope) throws -> (start: Date, end: Date)? {
        switch scope {
        case .all:
            return nil
        case let .dateRange(start, end):
            let startOfDay = calendar.startOfDay(for: start)
            let endOfDay = calendar.startOfDay(for: end)
            guard startOfDay <= endOfDay else {
                throw ExportError.invalidDateRange
            }
            guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endOfDay) else {
                throw ExportError.invalidDateRange
            }
            return (startOfDay, exclusiveEnd)
        }
    }
}
