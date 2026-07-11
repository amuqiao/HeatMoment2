import XCTest
@testable import Moodments

final class MarkdownExportRendererTests: XCTestCase {
    func testRendererEscapesInlineMarkdownAndKeepsBodyText() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let snapshot = ExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 0),
            moments: [
                ExportMoment(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    title: "#标题[草稿]",
                    bodyText: "第一行\r\n第二行",
                    occurredAt: Date(timeIntervalSince1970: 60),
                    mood: .normal,
                    tagNames: ["a+b"],
                    assets: [ExportAsset(id: UUID(), data: pngData)]
                )
            ]
        )
        let renderer = MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)

        let document = renderer.render(snapshot: snapshot)

        XCTAssertTrue(document.markdown.contains("## \\#标题\\[草稿\\]"))
        XCTAssertTrue(document.markdown.contains("- 标签：#a\\+b"))
        XCTAssertTrue(document.markdown.contains("第一行\n第二行"))
        XCTAssertTrue(
            document.markdown.contains(
                "![照片 1](assets/moment-11111111-1111-1111-1111-111111111111-image-1.png)"
            )
        )
        XCTAssertEqual(document.assets.count, 1)
    }
}
