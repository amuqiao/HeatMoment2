import XCTest
@testable import HeatMoment

class MarkdownExportServiceTestCase: XCTestCase {
    var outputRootURL: URL!

    override func setUpWithError() throws {
        outputRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(Self.self)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputRootURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let outputRootURL, FileManager.default.fileExists(atPath: outputRootURL.path) {
            try FileManager.default.removeItem(at: outputRootURL)
        }
        outputRootURL = nil
    }

    func makeCanonicalFixture() throws -> MarkdownExportFixture {
        let assetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MarkdownExportCanonicalAssets-\(UUID().uuidString)",
            isDirectory: true
        )
        return MarkdownExportFixture(
            runtime: try CanonicalLibraryRuntime.makeInMemoryForTests(
                assetDirectoryURL: assetDirectory
            ),
            assetDirectory: assetDirectory
        )
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

struct MarkdownExportFixture {
    let runtime: CanonicalLibraryRuntime
    let assetDirectory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: assetDirectory)
    }
}
