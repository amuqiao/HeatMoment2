import XCTest
@testable import HeatMoment

/// `Mood` 契约测试：见 `docs/product-mental-model.md` §1——rawValue 顺序一旦发布即视为
/// 持久化契约，本测试保护顺序与数量不被误改。
final class MoodTests: XCTestCase {
    func testAllCasesCountIsEight() {
        XCTAssertEqual(Mood.allCases.count, 8)
    }

    func testRawValueOrderIsStable() {
        let firstHalf: [Mood] = [.normal, .happy, .sad, .anxious]
        let secondHalf: [Mood] = [.fearful, .angry, .disgusted, .motivated]
        let expected = firstHalf + secondHalf
        XCTAssertEqual(Mood.allCases, expected, "Mood.allCases 顺序必须等于 rawValue 升序契约")
        for (index, mood) in expected.enumerated() {
            XCTAssertEqual(mood.rawValue, index, "\(mood) 的 rawValue 偏离契约位置")
        }
    }

    func testEmojiMappingExistsForAllCases() {
        for mood in Mood.allCases {
            XCTAssertFalse(mood.emoji.isEmpty, "\(mood) 缺少 emoji 映射")
        }
    }

    func testLocalizedNameKeyMappingExistsForAllCases() {
        for mood in Mood.allCases {
            XCTAssertTrue(
                mood.localizedNameKey.hasPrefix("mood.")
                    && mood.localizedNameKey.hasSuffix(".name"),
                "\(mood) 的 localizedNameKey 不符合 \"mood.<case>.name\" 约定"
            )
        }
    }
}
