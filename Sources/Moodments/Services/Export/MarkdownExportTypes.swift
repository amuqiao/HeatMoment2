import Foundation

struct MarkdownExportSnapshot: Sendable, Equatable {
    let exportedAt: Date
    let moments: [MarkdownExportMoment]
}

struct MarkdownExportMoment: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let bodyText: String
    let occurredAt: Date
    let mood: Mood
    let tagNames: [String]
    let assets: [MarkdownExportAsset]
}

struct MarkdownExportAsset: Sendable, Equatable, Identifiable {
    let id: UUID
    let data: Data
}

struct MarkdownExportDocument: Sendable, Equatable {
    let markdown: String
    let assets: [MarkdownExportRenderedAsset]
}

struct MarkdownExportRenderedAsset: Sendable, Equatable {
    let relativePath: String
    let data: Data
}

struct MarkdownExportResult: Sendable, Equatable {
    let packageDirectoryURL: URL
    let markdownFileURL: URL
    let fileName: String
    let momentCount: Int
    let assetCount: Int
}

enum MarkdownExportError: Error, Equatable {
    case missingApplicationSupportDirectory
    case markdownEncodingFailed
    case cleanupFailed(original: String, cleanup: String)
}
