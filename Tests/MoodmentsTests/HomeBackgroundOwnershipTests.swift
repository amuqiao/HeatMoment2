import XCTest

final class HomeBackgroundOwnershipTests: XCTestCase {
    func testContextSurfacesDoNotInstantiateHomeSceneBackground() throws {
        let root = repositoryRoot()
        let files = [
            "Sources/Moodments/Features/Timeline/TimelineHomeChromeView.swift",
            "Sources/Moodments/Features/Heatmap/YearHeatmapView.swift",
        ]

        for file in files {
            let source = try String(
                contentsOf: root.appendingPathComponent(file),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains("HomeSceneBackgroundView()"),
                "\(file) 不应直接实例化首页背景；上下文 surface 只能覆盖在首页唯一背景之上。"
            )
        }
    }

    private func repositoryRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
