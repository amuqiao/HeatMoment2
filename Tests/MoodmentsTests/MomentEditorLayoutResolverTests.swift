import XCTest
@testable import Moodments

final class MomentEditorLayoutResolverTests: XCTestCase {
    func testTopChromeToSelectorGapDirectlyControlsContentTopInset() {
        let layout = MomentEditorLayoutResolver.resolve(
            tokens: MomentEditorLayoutTokens(topChromeToSelectorGap: 4),
            scale: TimelineResponsiveScale(viewportWidth: 390)
        )

        XCTAssertEqual(layout.topChromeToSelectorGap, 4)
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
        XCTAssertEqual(layout.selectorHorizontalPadding, 16)
        XCTAssertEqual(layout.contentInsets.top, layout.topChromeToSelectorGap)
    }

    func testResponsiveScaleTightensVerticalBreathingOnNarrowScreens() {
        let compact = MomentEditorLayoutResolver.resolve(
            tokens: MomentEditorLayoutTokens(topChromeToSelectorGap: 10),
            scale: TimelineResponsiveScale(viewportWidth: 320)
        )

        XCTAssertEqual(compact.topChromeToSelectorGap, 9)
    }
}
