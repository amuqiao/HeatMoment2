import Foundation

protocol ExportSnapshotProviding: Sendable {
    func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot
}

struct ExportService {
    private let snapshotProvider: any ExportSnapshotProviding
    private let outputRootURL: URL?
    private let markdownRenderer: MarkdownExportRenderer
    private let pdfRenderer: PDFExportRenderer

    init(
        snapshotProvider: any ExportSnapshotProviding,
        outputRootURL: URL? = nil,
        markdownRenderer: MarkdownExportRenderer = MarkdownExportRenderer(),
        pdfRenderer: PDFExportRenderer = PDFExportRenderer()
    ) {
        self.snapshotProvider = snapshotProvider
        self.outputRootURL = outputRootURL
        self.markdownRenderer = markdownRenderer
        self.pdfRenderer = pdfRenderer
    }

    func exportAll(format: ExportFormat, now: Date = .now) async throws -> ExportResult {
        let request = ExportRequest(
            scope: .all,
            format: format,
            includePhotos: true,
            requestedAt: now
        )
        return try await export(request: request)
    }

    func export(request: ExportRequest) async throws -> ExportResult {
        let snapshot = try await snapshotProvider.makeSnapshot(request: request)
        guard !snapshot.moments.isEmpty else {
            throw ExportError.emptyExport
        }
        try Task.checkCancellation()
        let outputRoot = outputRootURL ?? Self.defaultOutputRootURL(format: request.format)
        let markdownRenderer = markdownRenderer
        let pdfRenderer = pdfRenderer
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let writer = ExportFileWriter(outputRootURL: outputRoot)
            switch request.format {
            case .markdown:
                let document = markdownRenderer.render(snapshot: snapshot)
                try Task.checkCancellation()
                return try writer.writeMarkdown(document: document, snapshot: snapshot)
            case .pdf:
                let document = try pdfRenderer.render(snapshot: snapshot)
                try Task.checkCancellation()
                return try writer.writePDF(document: document, snapshot: snapshot)
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func cleanupTemporaryExports() throws {
        for format in ExportFormat.allCases {
            let writer = ExportFileWriter(outputRootURL: defaultOutputRootURL(format: format))
            try writer.cleanOutputRoot()
        }
    }

    private static func defaultOutputRootURL(format: ExportFormat) -> URL {
        let exportsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MoodmentsExports",
            isDirectory: true
        )
        return exportsDirectory.appendingPathComponent(
            format.outputDirectoryName,
            isDirectory: true
        )
    }
}

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

struct ExportFileWriter: Sendable {
    let outputRootURL: URL

    func writeMarkdown(
        document: MarkdownExportDocument,
        snapshot: ExportSnapshot
    ) throws -> ExportResult {
        try write(
            format: .markdown,
            exportedAt: snapshot.exportedAt,
            momentCount: snapshot.moments.count,
            assetCount: document.assets.count
        ) { locations in
            try writeMarkdownDocument(document, to: locations)
        }
    }

    func writePDF(document: PDFExportDocument, snapshot: ExportSnapshot) throws -> ExportResult {
        try write(
            format: .pdf,
            exportedAt: snapshot.exportedAt,
            momentCount: snapshot.moments.count,
            assetCount: snapshot.moments.reduce(0) { $0 + $1.assets.count }
        ) { locations in
            try writePDFDocument(document, to: locations)
        }
    }

    private func write(
        format: ExportFormat,
        exportedAt: Date,
        momentCount: Int,
        assetCount: Int,
        writeDocument: (ExportOutputLocations) throws -> Void
    ) throws -> ExportResult {
        try prepareOutputRoot()
        let fileName = "Moodments-\(Self.fileTimestamp(exportedAt)).\(format.fileExtension)"
        let locations = makeOutputLocations(
            exportedAt: exportedAt,
            fileName: fileName
        )

        do {
            try Task.checkCancellation()
            try writeDocument(locations)
        } catch {
            let originalError = error
            try cleanupFailedPackage(locations.packageDirectory, originalError: originalError)
            throw originalError
        }

        return ExportResult(
            format: format,
            packageDirectoryURL: locations.packageDirectory,
            fileURL: locations.file,
            fileName: fileName,
            momentCount: momentCount,
            assetCount: assetCount
        )
    }

    private func prepareOutputRoot() throws {
        try cleanOutputRoot()
    }

    func cleanOutputRoot() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputRootURL, withIntermediateDirectories: true)
        let existingPackages = try fileManager.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        for package in existingPackages where package.lastPathComponent.hasPrefix("Moodments-") {
            try fileManager.removeItem(at: package)
        }
    }

    private func makeOutputLocations(
        exportedAt: Date,
        fileName: String
    ) -> ExportOutputLocations {
        // swiftlint:disable trailing_comma
        let directoryName = [
            "Moodments",
            Self.fileTimestamp(exportedAt),
            UUID().uuidString,
        ].joined(separator: "-")
        // swiftlint:enable trailing_comma
        let packageDirectory = outputRootURL.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        return ExportOutputLocations(
            packageDirectory: packageDirectory,
            file: packageDirectory.appendingPathComponent(fileName)
        )
    }

    private func writeMarkdownDocument(
        _ document: MarkdownExportDocument,
        to locations: ExportOutputLocations
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: locations.packageDirectory,
            withIntermediateDirectories: false
        )
        for asset in document.assets {
            try Task.checkCancellation()
            let assetURL = locations.packageDirectory.appendingPathComponent(asset.relativePath)
            try fileManager.createDirectory(
                at: assetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try asset.data.write(to: assetURL, options: .atomic)
        }
        guard let markdownData = document.markdown.data(using: .utf8) else {
            throw ExportError.markdownEncodingFailed
        }
        try Task.checkCancellation()
        try markdownData.write(to: locations.file, options: .atomic)
    }

    private func writePDFDocument(
        _ document: PDFExportDocument,
        to locations: ExportOutputLocations
    ) throws {
        try FileManager.default.createDirectory(
            at: locations.packageDirectory,
            withIntermediateDirectories: false
        )
        try Task.checkCancellation()
        try document.data.write(to: locations.file, options: .atomic)
    }

    private func cleanupFailedPackage(_ packageDirectory: URL, originalError: Error) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: packageDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: packageDirectory)
        } catch {
            throw ExportError.cleanupFailed(
                original: String(describing: originalError),
                cleanup: String(describing: error)
            )
        }
    }

    private static func fileTimestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}

private struct ExportOutputLocations {
    let packageDirectory: URL
    let file: URL
}
