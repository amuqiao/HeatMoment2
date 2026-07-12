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
