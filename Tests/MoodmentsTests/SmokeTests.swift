import XCTest
@testable import Moodments

/// 阶段 0 冒烟：证明工程可编译、测试可跑。阶段 1 起补 Mood/限额/软删除等契约测试。
final class SmokeTests: XCTestCase {
    func testScaffoldCompilesAndRuns() {
        XCTAssertTrue(true, "脚手架就绪")
    }
}
