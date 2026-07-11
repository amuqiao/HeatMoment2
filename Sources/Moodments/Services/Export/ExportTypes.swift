import Foundation

enum ExportFormat: String, CaseIterable, Sendable, Equatable {
    case markdown
    case pdf

    var displayName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .pdf:
            return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .pdf:
            return "pdf"
        }
    }

    var outputDirectoryName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .pdf:
            return "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .markdown:
            return "doc.plaintext"
        case .pdf:
            return "doc.richtext"
        }
    }

    var generateTitle: String {
        "生成 \(displayName)"
    }

    var exportingTitle: String {
        "正在生成..."
    }

    var shareTitle: String {
        switch self {
        case .markdown:
            return "分享导出目录"
        case .pdf:
            return "分享 PDF"
        }
    }
}

struct ExportRequest: Sendable, Equatable {
    let scope: ExportScope
    let format: ExportFormat
    let includePhotos: Bool
    let requestedAt: Date

    init(
        scope: ExportScope,
        format: ExportFormat,
        includePhotos: Bool,
        requestedAt: Date = .now
    ) {
        self.scope = scope
        self.format = format
        self.includePhotos = includePhotos
        self.requestedAt = requestedAt
    }
}

enum ExportScope: Sendable, Equatable {
    case all
    case dateRange(start: Date, end: Date)
}

struct ExportDateBounds: Sendable, Equatable {
    let earliest: Date
    let latest: Date
}

struct ExportSnapshot: Sendable, Equatable {
    let exportedAt: Date
    let scope: ExportScope
    let includePhotos: Bool
    let moments: [ExportMoment]
}

struct ExportMoment: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let bodyText: String
    let occurredAt: Date
    let mood: Mood
    let tagNames: [String]
    let assets: [ExportAsset]
}

struct ExportAsset: Sendable, Equatable, Identifiable {
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

struct PDFExportDocument: Sendable, Equatable {
    let data: Data
}

struct ExportResult: Sendable, Equatable {
    let format: ExportFormat
    let packageDirectoryURL: URL
    let fileURL: URL
    let fileName: String
    let momentCount: Int
    let assetCount: Int
}

enum ExportError: Error, Equatable {
    case invalidDateRange
    case emptyExport
    case markdownEncodingFailed
    case pdfImageDecodingFailed(momentID: UUID, assetID: UUID)
    case pdfTextLayoutFailed
    case cleanupFailed(original: String, cleanup: String)
}

extension String {
    var trimmedForExportTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }
}
