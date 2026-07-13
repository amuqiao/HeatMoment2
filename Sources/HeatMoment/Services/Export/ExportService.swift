import Foundation

protocol ExportSnapshotProviding: Sendable {
    func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot
}

protocol ExportServicing: Sendable {
    func cleanupTemporaryExports() throws
    func exportDateBounds() async throws -> ExportDateBounds?
    func prepareShareTransaction(request: ExportRequest) async throws -> ExportShareTransaction
    func finishShareTransaction(_ transaction: ExportShareTransaction) throws
}

struct CanonicalExportService: ExportServicing {
    let repository: CanonicalLibraryRepository

    func cleanupTemporaryExports() throws {
        try ExportService.cleanupTemporaryExports()
    }

    func exportDateBounds() async throws -> ExportDateBounds? {
        try await repository.exportDateBounds()
    }

    func prepareShareTransaction(request: ExportRequest) async throws -> ExportShareTransaction {
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: repository)
        )
        return try await service.prepareShareTransaction(request: request)
    }

    func finishShareTransaction(_ transaction: ExportShareTransaction) throws {
        try ExportService.finishShareTransaction(transaction)
    }
}

#if DEBUG
    struct PreviewExportService: ExportServicing {
        func cleanupTemporaryExports() throws {}

        func exportDateBounds() async throws -> ExportDateBounds? {
            let date = Date(timeIntervalSince1970: 3_600)
            return ExportDateBounds(earliest: date, latest: date)
        }

        func prepareShareTransaction(
            request: ExportRequest
        ) async throws -> ExportShareTransaction {
            let service = ExportService(snapshotProvider: PreviewExportSnapshotProvider())
            return try await service.prepareShareTransaction(request: request)
        }

        func finishShareTransaction(_ transaction: ExportShareTransaction) throws {
            try ExportService.finishShareTransaction(transaction)
        }
    }

    private struct PreviewExportSnapshotProvider: ExportSnapshotProviding {
        func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot {
            ExportSnapshot(
                exportedAt: request.requestedAt,
                scope: request.scope,
                includePhotos: request.includePhotos,
                moments: [
                    ExportMoment(
                        id: UUID(
                            uuid: (
                                0x33, 0x33, 0x33, 0x33,
                                0x33, 0x33,
                                0x33, 0x33,
                                0x33, 0x33,
                                0x33, 0x33, 0x33, 0x33, 0x33, 0x33
                            )
                        ),
                        title: "预览导出",
                        bodyText: "用于 SwiftUI Preview 的导出样例。",
                        occurredAt: Date(timeIntervalSince1970: 3_600),
                        mood: .happy,
                        tagNames: ["预览"],
                        assets: []
                    )
                ]
            )
        }
    }

    struct DebugFailingPDFExportService: ExportServicing {
        func cleanupTemporaryExports() throws {
            try ExportService.cleanupTemporaryExports()
        }

        func exportDateBounds() async throws -> ExportDateBounds? {
            let date = Date(timeIntervalSince1970: 3_600)
            return ExportDateBounds(earliest: date, latest: date)
        }

        func prepareShareTransaction(
            request: ExportRequest
        ) async throws -> ExportShareTransaction {
            let service = ExportService(snapshotProvider: DebugFailingPDFExportSnapshotProvider())
            return try await service.prepareShareTransaction(request: request)
        }

        func finishShareTransaction(_ transaction: ExportShareTransaction) throws {
            try ExportService.finishShareTransaction(transaction)
        }
    }

    private struct DebugFailingPDFExportSnapshotProvider: ExportSnapshotProviding {
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

    func prepareShareTransaction(request: ExportRequest) async throws -> ExportShareTransaction {
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

    func finishShareTransaction(_ transaction: ExportShareTransaction) throws {
        let writer = ExportFileWriter(
            outputRootURL: outputRootURL ?? Self.defaultOutputRootURL(format: transaction.format)
        )
        try writer.cleanOutputRoot()
    }

    static func finishShareTransaction(_: ExportShareTransaction) throws {
        try cleanupTemporaryExports()
    }

    static func cleanupTemporaryExports() throws {
        for format in ExportFormat.allCases {
            let writer = ExportFileWriter(outputRootURL: defaultOutputRootURL(format: format))
            try writer.cleanOutputRoot()
        }
    }

    private static func defaultOutputRootURL(format: ExportFormat) -> URL {
        let exportsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HeatMomentExports",
            isDirectory: true
        )
        return exportsDirectory.appendingPathComponent(
            format.outputDirectoryName,
            isDirectory: true
        )
    }
}
