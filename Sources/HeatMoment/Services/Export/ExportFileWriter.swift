import Foundation

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
        let fileName = "HeatMoment-\(Self.fileTimestamp(exportedAt)).\(format.fileExtension)"
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
        for package in existingPackages where package.lastPathComponent.hasPrefix("HeatMoment-") {
            try fileManager.removeItem(at: package)
        }
    }

    private func makeOutputLocations(
        exportedAt: Date,
        fileName: String
    ) -> ExportOutputLocations {
        // swiftlint:disable trailing_comma
        let directoryName = [
            "HeatMoment",
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
