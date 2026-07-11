import Foundation
import SwiftData

struct MarkdownExportService {
    private let modelContainer: ModelContainer
    private let outputRootURL: URL?
    private let renderer: MarkdownExportRenderer

    init(
        modelContainer: ModelContainer,
        outputRootURL: URL? = nil,
        renderer: MarkdownExportRenderer = MarkdownExportRenderer()
    ) {
        self.modelContainer = modelContainer
        self.outputRootURL = outputRootURL
        self.renderer = renderer
    }

    func exportAll(now: Date = .now) async throws -> MarkdownExportResult {
        let store = SwiftDataMarkdownExportSnapshotStore(modelContainer: modelContainer)
        let snapshot = try await store.makeSnapshot(exportedAt: now)
        let outputRoot = try outputRootURL ?? Self.defaultOutputRootURL()
        let renderer = renderer
        return try await Task.detached(priority: .userInitiated) {
            let document = renderer.render(snapshot: snapshot)
            return try MarkdownExportFileWriter(outputRootURL: outputRoot)
                .write(document: document, snapshot: snapshot)
        }.value
    }

    private static func defaultOutputRootURL() throws -> URL {
        let exportsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MoodmentsExports",
            isDirectory: true
        )
        return exportsDirectory.appendingPathComponent(
            "Markdown",
            isDirectory: true
        )
    }
}

@ModelActor
actor SwiftDataMarkdownExportSnapshotStore {
    func makeSnapshot(exportedAt: Date) throws -> MarkdownExportSnapshot {
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedFlag == false },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        let moments = try modelContext.fetch(descriptor).map { moment in
            MarkdownExportMoment(
                id: moment.id,
                title: moment.title,
                bodyText: moment.bodyText,
                occurredAt: moment.occurredAt,
                mood: moment.mood,
                tagNames: sortedTagNames(moment.tags),
                assets: sortedAssets(moment.images)
            )
        }
        return MarkdownExportSnapshot(exportedAt: exportedAt, moments: moments)
    }

    private func sortedTagNames(_ tags: [Tag]) -> [String] {
        tags
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func sortedAssets(_ images: [MomentImage]) -> [MarkdownExportAsset] {
        images
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { MarkdownExportAsset(id: $0.id, data: $0.imageData) }
    }
}

struct MarkdownExportFileWriter: Sendable {
    let outputRootURL: URL

    func write(
        document: MarkdownExportDocument,
        snapshot: MarkdownExportSnapshot
    ) throws -> MarkdownExportResult {
        try prepareOutputRoot()
        let markdownFileName = "Moodments-\(Self.fileTimestamp(snapshot.exportedAt)).md"
        let locations = makeOutputLocations(
            exportedAt: snapshot.exportedAt,
            markdownFileName: markdownFileName
        )

        do {
            try writeDocument(document, to: locations)
        } catch {
            let originalError = error
            try cleanupFailedPackage(locations.packageDirectory, originalError: originalError)
            throw originalError
        }

        return MarkdownExportResult(
            packageDirectoryURL: locations.packageDirectory,
            markdownFileURL: locations.markdownFile,
            fileName: markdownFileName,
            momentCount: snapshot.moments.count,
            assetCount: document.assets.count
        )
    }

    private func prepareOutputRoot() throws {
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
        markdownFileName: String
    ) -> MarkdownExportOutputLocations {
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
        return MarkdownExportOutputLocations(
            packageDirectory: packageDirectory,
            markdownFile: packageDirectory.appendingPathComponent(markdownFileName)
        )
    }

    private func writeDocument(
        _ document: MarkdownExportDocument,
        to locations: MarkdownExportOutputLocations
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: locations.packageDirectory,
            withIntermediateDirectories: false
        )
        for asset in document.assets {
            let assetURL = locations.packageDirectory.appendingPathComponent(asset.relativePath)
            try fileManager.createDirectory(
                at: assetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try asset.data.write(to: assetURL, options: .atomic)
        }
        guard let markdownData = document.markdown.data(using: .utf8) else {
            throw MarkdownExportError.markdownEncodingFailed
        }
        try markdownData.write(to: locations.markdownFile, options: .atomic)
    }

    private func cleanupFailedPackage(_ packageDirectory: URL, originalError: Error) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: packageDirectory.path) else { return }
        do {
            try fileManager.removeItem(at: packageDirectory)
        } catch {
            throw MarkdownExportError.cleanupFailed(
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

private struct MarkdownExportOutputLocations {
    let packageDirectory: URL
    let markdownFile: URL
}
