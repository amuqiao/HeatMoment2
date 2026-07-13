import XCTest
@testable import HeatMoment

/// `ErrorPresenter` 接线验收（见 `docs/plans/implementation-plan.md` 阶段6 决策3、
/// Support/ErrorPresenter.swift 头部注释）：写失败 → `currentError` 被 set（用户可见的驱动源），
/// `dismiss()` 清空；本类型只负责「展示」，不改变、不伪造任何业务状态（该保证由调用方各自的
/// 「失败不 dismiss / reload 真相源」逻辑落实，此处只验证 `ErrorPresenter` 自身状态机正确）。
@MainActor
final class ErrorPresenterTests: XCTestCase {
    private enum SampleError: Error { case sample }

    func testReportSetsCurrentError() {
        let presenter = ErrorPresenter()

        presenter.report(message: "保存失败，请重试。", underlying: SampleError.sample)

        XCTAssertNotNil(presenter.currentError)
        XCTAssertEqual(presenter.currentError?.message, "保存失败，请重试。")
    }

    func testDismissClearsCurrentError() {
        let presenter = ErrorPresenter()
        presenter.report(message: "保存失败，请重试。", underlying: SampleError.sample)

        presenter.dismiss()

        XCTAssertNil(presenter.currentError)
    }

    /// 连续两次不同的失败上报，`currentError` 应反映最新一次（各自独立的 `UserFacingError`，
    /// `id` 不同，供 `.alert` 的 `Identifiable` 驱动正确重新呈现）。
    func testConsecutiveReportsProduceDistinctErrors() {
        let presenter = ErrorPresenter()

        presenter.report(message: "第一次失败", underlying: SampleError.sample)
        let first = presenter.currentError

        presenter.report(message: "第二次失败", underlying: SampleError.sample)
        let second = presenter.currentError

        XCTAssertNotEqual(first?.id, second?.id)
        XCTAssertEqual(second?.message, "第二次失败")
    }
}
