import XCTest
@testable import HeatMoment

final class MomentEditorLayoutResolverTests: XCTestCase {
    func testToolbarToSelectorGapDirectlyControlsContentTopInset() {
        let layout = MomentEditorLayoutResolver.resolve(
            tokens: MomentEditorLayoutTokens(toolbarToSelectorGap: 4),
            scale: TimelineResponsiveScale(viewportWidth: 390)
        )

        XCTAssertEqual(layout.toolbarToSelectorGap, 4)
        XCTAssertEqual(layout.contentInsets.top, 4)
    }

    func testSelectorAndTextPanelGapsAreIndependentSemanticTokens() {
        let layout = MomentEditorLayoutResolver.resolve(
            tokens: MomentEditorLayoutTokens(
                selectorToTextPanelGap: 12,
                textPanelToPhotoSectionGap: 24
            ),
            scale: TimelineResponsiveScale(viewportWidth: 390)
        )

        XCTAssertEqual(layout.selectorToTextPanelGap, 12)
        XCTAssertEqual(layout.textPanelToPhotoSectionGap, 24)
    }

    func testEditorLayoutUsesEditorOwnedDefaultInsetsWithoutOwningGlobalVerticalInset() {
        let layout = MomentEditorLayoutMetrics.standard

        XCTAssertEqual(layout.pageBottomInset, 56)
        XCTAssertEqual(layout.pageHorizontalInset, 16)
        XCTAssertEqual(layout.selectorMinHeight, 40)
        XCTAssertEqual(layout.selectorHorizontalPadding, 16)
        XCTAssertEqual(layout.bodyMinHeight, 132)
        XCTAssertEqual(layout.contentInsets.top, layout.toolbarToSelectorGap)
    }

    func testResponsiveScaleTightensVerticalBreathingOnNarrowScreens() {
        let compact = MomentEditorLayoutResolver.resolve(
            tokens: MomentEditorLayoutTokens(toolbarToSelectorGap: 10),
            scale: TimelineResponsiveScale(viewportWidth: 320)
        )

        XCTAssertEqual(compact.toolbarToSelectorGap, 9)
    }
}
