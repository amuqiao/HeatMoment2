import CoreText
import Foundation
import UIKit

struct PDFExportRenderer: Sendable {
    private let pageSize: CGSize
    private let pageMargin: CGFloat
    private var calendar: Calendar

    init(
        pageSize: CGSize = CGSize(width: 595.2, height: 841.8),
        pageMargin: CGFloat = 44,
        timeZone: TimeZone = .current
    ) {
        self.pageSize = pageSize
        self.pageMargin = pageMargin
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func render(snapshot: ExportSnapshot) throws -> PDFExportDocument {
        let format = UIGraphicsPDFRendererFormat()
        // swiftlint:disable trailing_comma
        format.documentInfo = [
            kCGPDFContextTitle as String: "时刻导出",
            kCGPDFContextCreator as String: "Moodments",
        ]
        // swiftlint:enable trailing_comma
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        var renderError: Error?

        let data = renderer.pdfData { context in
            var layout = PDFExportPageLayout(
                context: context,
                pageSize: pageSize,
                margin: pageMargin
            )
            layout.beginPage()

            do {
                try drawHeader(snapshot: snapshot, layout: &layout)
                for (index, moment) in snapshot.moments.enumerated() {
                    try Task.checkCancellation()
                    try draw(moment: moment, isFirst: index == 0, layout: &layout)
                }
            } catch {
                renderError = error
            }
        }

        if let renderError {
            throw renderError
        }
        return PDFExportDocument(data: data)
    }

    private func drawHeader(snapshot: ExportSnapshot, layout: inout PDFExportPageLayout) throws {
        try layout.drawText(
            "时刻导出",
            font: .systemFont(ofSize: 28, weight: .bold),
            color: .label,
            spacingAfter: 12
        )
        try layout.drawText(
            "导出时间：\(formattedDate(snapshot.exportedAt))\n时刻数量：\(snapshot.moments.count)",
            font: .systemFont(ofSize: 11, weight: .regular),
            color: .secondaryLabel,
            spacingAfter: 22
        )
    }

    private func draw(
        moment: ExportMoment,
        isFirst: Bool,
        layout: inout PDFExportPageLayout
    ) throws {
        if !isFirst {
            layout.drawSeparator()
        }
        try layout.drawText(
            moment.title.trimmedForExportTitle,
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: .label,
            spacingAfter: 8
        )
        try layout.drawText(
            // swiftlint:disable trailing_comma
            [
                "发生时间：\(formattedDate(moment.occurredAt))",
                "心情：\(moment.mood.emoji) \(moment.mood.displayName)",
                "标签：\(tagText(moment.tagNames))",
                // swiftlint:enable trailing_comma
            ].joined(separator: "\n"),
            font: .systemFont(ofSize: 10, weight: .regular),
            color: .secondaryLabel,
            spacingAfter: 10
        )

        let bodyText = normalizedBody(moment.bodyText)
        if !bodyText.isEmpty {
            try layout.drawText(
                bodyText,
                font: .systemFont(ofSize: 12, weight: .regular),
                color: .label,
                spacingAfter: 12
            )
        }

        for (assetIndex, asset) in moment.assets.enumerated() {
            try Task.checkCancellation()
            guard let image = UIImage(data: asset.data) else {
                throw ExportError.pdfImageDecodingFailed(momentID: moment.id, assetID: asset.id)
            }
            try layout.drawImage(image, caption: "照片 \(assetIndex + 1)")
        }
    }

    private func tagText(_ tagNames: [String]) -> String {
        guard !tagNames.isEmpty else { return "无" }
        return tagNames.map { "#\($0)" }.joined(separator: " ")
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
}

private struct PDFExportPageLayout {
    private let context: UIGraphicsPDFRendererContext
    private let pageSize: CGSize
    private let margin: CGFloat
    private var cursorY: CGFloat = 0

    init(context: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat) {
        self.context = context
        self.pageSize = pageSize
        self.margin = margin
    }

    mutating func beginPage() {
        context.beginPage()
        cursorY = margin
    }

    mutating func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        spacingAfter: CGFloat
    ) throws {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 3
        // swiftlint:disable trailing_comma
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]
        )
        // swiftlint:enable trailing_comma
        try drawPaginated(attributed, spacingAfter: spacingAfter)
    }

    mutating func drawSeparator() {
        ensureSpace(18)
        UIColor.separator.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: cursorY))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: cursorY))
        path.lineWidth = 0.5
        path.stroke()
        cursorY += 18
    }

    mutating func drawImage(_ image: UIImage, caption: String) throws {
        let maxImageHeight = min(260, contentHeight)
        let imageSize = aspectFit(
            image.size,
            maxSize: CGSize(width: contentWidth, height: maxImageHeight)
        )
        ensureSpace(imageSize.height + 34)
        try drawText(
            caption,
            font: .systemFont(ofSize: 10, weight: .regular),
            color: .secondaryLabel,
            spacingAfter: 6
        )
        ensureSpace(imageSize.height + 14)
        let imageRect = CGRect(
            x: margin,
            y: cursorY,
            width: imageSize.width,
            height: imageSize.height
        )
        image.draw(in: imageRect)
        cursorY += imageSize.height + 14
    }

    private mutating func drawPaginated(
        _ attributed: NSAttributedString,
        spacingAfter: CGFloat
    ) throws {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var location = 0
        while location < attributed.length {
            try Task.checkCancellation()
            let availableHeight = pageSize.height - margin - cursorY
            if availableHeight < 24 {
                beginPage()
                continue
            }

            let remainingRange = CFRange(
                location: location,
                length: attributed.length - location
            )
            var fitRange = CFRange()
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                remainingRange,
                nil,
                CGSize(width: contentWidth, height: availableHeight),
                &fitRange
            )
            if fitRange.length <= 0 {
                if cursorY > margin {
                    beginPage()
                    continue
                }
                throw ExportError.pdfTextLayoutFailed
            }

            let drawHeight = min(ceil(suggestedSize.height) + 2, availableHeight)
            drawTextFrame(
                framesetter: framesetter,
                range: CFRange(location: location, length: fitRange.length),
                rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: drawHeight)
            )
            location += fitRange.length
            cursorY += drawHeight
            if location < attributed.length {
                beginPage()
            }
        }
        cursorY += spacingAfter
    }

    private func drawTextFrame(
        framesetter: CTFramesetter,
        range: CFRange,
        rect: CGRect
    ) {
        let cgContext = context.cgContext
        cgContext.saveGState()
        cgContext.textMatrix = .identity
        cgContext.translateBy(x: rect.minX, y: rect.maxY)
        cgContext.scaleBy(x: 1, y: -1)

        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: rect.size))
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        CTFrameDraw(frame, cgContext)

        cgContext.restoreGState()
    }

    private mutating func ensureSpace(_ requiredHeight: CGFloat) {
        if cursorY + requiredHeight > pageSize.height - margin {
            beginPage()
        }
    }

    private func aspectFit(_ size: CGSize, maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: maxSize.width, height: maxSize.width)
        }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private var contentWidth: CGFloat {
        pageSize.width - margin * 2
    }

    private var contentHeight: CGFloat {
        pageSize.height - margin * 2
    }
}
