import CoreImage
import UIKit
import XCTest

/// 组合式主题验收（见 `docs/product-mental-model.md` 公理1「心情色一致性」、
/// `docs/design/05-design-system.md` §5.3、`docs/plans/implementation-plan.md` 阶段6）：
///
/// **核心不变量**：切**主色**时 FAB/强调随之变化，但心情色 / 危险色**不变**——
/// 心情色/危险色独立于主色的结构性保证已由 `MoodColorPaletteTests`（单元级，签名不含
/// `AccentColorOption` 参数）覆盖；本文件在真实运行时 UI 层面复核主色确实驱动了强调色
/// （FAB 颜色随之改变），并确认外观选项的即时生效（乐观更新：点选后立即反映为选中态）。
final class ThemeSwitchUITests: XCTestCase {
    /// 切主色 → `AppearanceThemeView` 选中态立即从旧选项移到新选项（即时生效，无需保存按钮）；
    /// 关闭设置回到时间轴后，FAB 的渲染颜色应随之改变（真实视觉验证「主色驱动强调色」）。
    func testSwitchingAccentColorUpdatesSelectionAndFABColor() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        let colorBeforeSwitch = averageColor(of: fab)

        openAppearanceThemeView(app)

        // 默认主色为「紫罗兰」，切到色值差异明显的「红色」。
        let violetOption = app.buttons["appearanceAccentOption-violet"]
        let redOption = app.buttons["appearanceAccentOption-red"]
        XCTAssertTrue(violetOption.waitForExistence(timeout: 5))
        XCTAssertTrue(redOption.waitForExistence(timeout: 5))
        XCTAssertTrue(violetOption.isSelected, "默认主色应为紫罗兰")

        redOption.tap()

        XCTAssertTrue(redOption.isSelected, "点选后应立即变为选中态（乐观更新，无需保存按钮）")
        XCTAssertFalse(violetOption.isSelected, "旧选项应立即失去选中态")

        closeSettings(app)

        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        let colorAfterSwitch = averageColor(of: fab)
        XCTAssertTrue(
            colorDistance(colorBeforeSwitch, colorAfterSwitch) > 0.15,
            "切主色后 FAB 渲染颜色应有明显变化（紫罗兰→红色）"
        )
    }

    /// 切**模式**（暗→亮）→ 立即生效：`AppearanceThemeView` 选中态随之切换；当前主色槽位
    /// （选中的仍是同一个 `AccentColorOption`）不因切模式而改变——只是该主色解析出的具体
    /// RGB 值随模式切到其亮/暗两态（05 §5.3.2），这与「心情色随模式切换」是同一层语义
    /// （见 `MoodColorPaletteTests`），但主色/模式与心情色是两套独立状态，互不影响。
    func testSwitchingModeUpdatesSelectionAndKeepsAccentSlotUnchanged() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        let darkOption = app.buttons["appearanceModeOption-dark"]
        let lightOption = app.buttons["appearanceModeOption-light"]
        XCTAssertTrue(darkOption.waitForExistence(timeout: 5))
        XCTAssertTrue(lightOption.waitForExistence(timeout: 5))
        XCTAssertTrue(darkOption.isSelected, "默认模式应为暗色")

        let violetOption = app.buttons["appearanceAccentOption-violet"]
        XCTAssertTrue(violetOption.waitForExistence(timeout: 5))
        XCTAssertTrue(violetOption.isSelected, "切模式前当前主色槽位为紫罗兰")

        lightOption.tap()

        XCTAssertTrue(lightOption.isSelected, "切模式应立即生效")
        XCTAssertFalse(darkOption.isSelected)
        XCTAssertTrue(violetOption.isSelected, "切模式不应改变当前选中的主色槽位（仍是紫罗兰）")
    }

    /// 切背景纹理（网格→点阵）即时生效：选中态立即切换，无需保存按钮。
    func testSwitchingBackgroundTextureUpdatesSelectionImmediately() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        let gridOption = app.buttons["appearanceTextureOption-grid"]
        let dotOption = app.buttons["appearanceTextureOption-dot"]
        XCTAssertTrue(gridOption.waitForExistence(timeout: 5))
        XCTAssertTrue(dotOption.waitForExistence(timeout: 5))
        XCTAssertTrue(gridOption.isSelected, "默认背景纹理应为网格线")

        dotOption.tap()

        XCTAssertTrue(dotOption.isSelected)
        XCTAssertFalse(gridOption.isSelected)
    }

    /// 切图片展示方式（滚动→轮播）即时生效：选中态立即切换，无需保存按钮。
    func testSwitchingImageDisplayModeUpdatesSelectionImmediately() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        // 「图片」分组在列表末尾，`List` 懒加载未滚到的行不会出现在无障碍树里，需先滚动到底。
        scrollToBottom(app)

        let scrollOption = app.buttons["appearanceImageModeOption-scroll"]
        let carouselOption = app.buttons["appearanceImageModeOption-carousel"]
        XCTAssertTrue(scrollOption.waitForExistence(timeout: 5))
        XCTAssertTrue(carouselOption.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollOption.isSelected, "默认图片展示方式应为滚动")

        carouselOption.tap()

        XCTAssertTrue(carouselOption.isSelected)
        XCTAssertFalse(scrollOption.isSelected)
    }

    // MARK: - Helpers

    private func openAppearanceThemeView(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let appearanceRow = app.buttons["settingsAppearanceRow"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        appearanceRow.tap()
    }

    /// 在 `AppearanceThemeView` 的 `List` 内下滑到底，使懒加载的末尾分组（「图片」）进入
    /// 无障碍树（`List` 对应 `UICollectionView`，未滚到的行不会实例化）。
    private func scrollToBottom(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeUp() }
    }

    private func closeSettings(_ app: XCUIApplication) {
        // 外观主题是设置栈内的子页，需先返回设置根页，再使用系统下滑关闭设置 sheet。
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.buttons["settingsAppearanceRow"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// 对给定元素截屏并取整体平均颜色（`CIAreaAverage`，避免猜测单点像素坐标/字节序）。
    private func averageColor(of element: XCUIElement) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let image = element.screenshot().image
        guard let ciImage = CIImage(image: image) else { return (0, 0, 0) }
        let extent = CIVector(
            x: ciImage.extent.origin.x, y: ciImage.extent.origin.y,
            z: ciImage.extent.size.width, w: ciImage.extent.size.height
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extent]),
              let output = filter.outputImage
        else { return (0, 0, 0) }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output, toBitmap: &bitmap, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil
        )
        return (CGFloat(bitmap[0]) / 255, CGFloat(bitmap[1]) / 255, CGFloat(bitmap[2]) / 255)
    }

    /// 归一化欧氏距离（0...约1.73），用于判断两次采样的颜色是否有「明显」差异。
    private func colorDistance(_ lhs: (r: CGFloat, g: CGFloat, b: CGFloat), _ rhs: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        let dr = lhs.r - rhs.r
        let dg = lhs.g - rhs.g
        let db = lhs.b - rhs.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
