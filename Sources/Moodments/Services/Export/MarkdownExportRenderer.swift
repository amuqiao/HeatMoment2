import Foundation

struct MarkdownExportRenderer: Sendable {
    private var calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func render(snapshot: ExportSnapshot) -> MarkdownExportDocument {
        // swiftlint:disable trailing_comma
        var lines: [String] = [
            "# 时刻导出",
            "",
            "- 导出时间：\(formattedDate(snapshot.exportedAt))",
            "- 时刻数量：\(snapshot.moments.count)",
            "",
        ]
        // swiftlint:enable trailing_comma
        var renderedAssets: [MarkdownExportRenderedAsset] = []

        for (momentIndex, moment) in snapshot.moments.enumerated() {
            lines.append("## \(escapedInline(moment.title.trimmedForExportTitle))")
            lines.append("")
            lines.append("- 发生时间：\(formattedDate(moment.occurredAt))")
            lines.append("- 心情：\(moment.mood.emoji) \(moment.mood.displayName)")
            lines.append("- 标签：\(tagText(moment.tagNames))")

            let bodyText = normalizedBody(moment.bodyText)
            if !bodyText.isEmpty {
                lines.append("")
                lines.append(bodyText)
            }

            if !moment.assets.isEmpty {
                lines.append("")
                for (assetIndex, asset) in moment.assets.enumerated() {
                    let relativePath = assetRelativePath(
                        momentID: moment.id,
                        assetIndex: assetIndex,
                        data: asset.data
                    )
                    lines.append("![照片 \(assetIndex + 1)](\(relativePath))")
                    renderedAssets.append(
                        MarkdownExportRenderedAsset(relativePath: relativePath, data: asset.data)
                    )
                }
            }

            if momentIndex < snapshot.moments.count - 1 {
                lines.append("")
                lines.append("---")
                lines.append("")
            }
        }

        return MarkdownExportDocument(
            markdown: lines.joined(separator: "\n"),
            assets: renderedAssets
        )
    }

    private func tagText(_ tagNames: [String]) -> String {
        guard !tagNames.isEmpty else { return "无" }
        return tagNames.map { "#\(escapedInline($0))" }.joined(separator: " ")
    }

    private func assetRelativePath(momentID: UUID, assetIndex: Int, data: Data) -> String {
        // swiftlint:disable trailing_comma
        let fileName = [
            "moment",
            momentID.uuidString.lowercased(),
            "image",
            "\(assetIndex + 1)",
        ].joined(separator: "-")
        // swiftlint:enable trailing_comma
        return "assets/\(fileName).\(Self.fileExtension(for: data))"
    }

    private func formattedDate(_ date: Date) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func normalizedBody(_ bodyText: String) -> String {
        bodyText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapedInline(_ value: String) -> String {
        let specialCharacters = Set("\\`*_{}[]()#+-.!")
        var result = ""
        for character in value {
            if specialCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    private static func fileExtension(for data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }
        if isHEIC(data) {
            return "heic"
        }
        return "bin"
    }

    private static func isHEIC(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        let signature = String(data: data.prefix(12), encoding: .ascii) ?? ""
        return signature.contains("ftypheic")
            || signature.contains("ftypheix")
            || signature.contains("ftyphevc")
            || signature.contains("ftypmif1")
    }
}
