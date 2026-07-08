import CoreImage
import UIKit
import XCTest

/// 组合式主题验收（见 `docs/product-mental-model.md` 公理1「心情色一致性」、
/// `docs/design/05-design-system.md` §5.3、`docs/plans/implementation-plan.md` 阶段6）：
///
/// **核心不变量**：切**主色**时 FAB/强调随之变化，但心情色 / 危险色**不变**——
/// 心情色/危险色独立于主色的结构性保证已由 `MoodPaletteTests`（单元级，palette 签名不含
/// `AccentColorOption` 参数）覆盖；本文件在真实运行时 UI 层面复核主色确实驱动了强调色
/// （FAB 颜色随之改变），并确认外观选项的即时生效（乐观更新：点选后立即反映为选中态）。
@MainActor
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

        // 切到色值差异明显且在当前列表位置可定位的「绿色」。
        let greenOption = app.buttons["appearanceAccentOption-green"]
        scrollUntilVisible(greenOption, app: app)
        XCTAssertTrue(greenOption.waitForExistence(timeout: 5))
        XCTAssertFalse(greenOption.isSelected, "切换前绿色不应是选中主色")

        greenOption.tap()

        XCTAssertTrue(greenOption.isSelected, "点选后应立即变为选中态（乐观更新，无需保存按钮）")

        closeSettings(app)

        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        let colorAfterSwitch = averageColor(of: fab)
        XCTAssertTrue(
            colorDistance(colorBeforeSwitch, colorAfterSwitch) > 0.15,
            "切主色后 FAB 渲染颜色应有明显变化（紫罗兰→绿色）"
        )
    }

    /// 主色区域必须是响应式网格，不能因为固定间距或固定总宽度把最后一个 swatch 顶出屏幕。
    func testAccentSwatchesStayInsideVisibleBounds() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        let visibleBounds = app.frame.insetBy(dx: 16, dy: 0)
        for option in ["purple", "red", "orange", "green", "cyan", "violet"] {
            let swatch = app.buttons["appearanceAccentOption-\(option)"]
            XCTAssertTrue(swatch.waitForExistence(timeout: 5), "主色 \(option) 应在外观页可见")
            XCTAssertTrue(
                visibleBounds.contains(swatch.frame),
                "主色 \(option) 不应溢出屏幕可见边界：\(swatch.frame)"
            )
        }
    }

    func testAppearanceTaskSectionsShareHorizontalBounds() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        let modeSection = app.otherElements["appearanceModeSection"]
        let accentSection = app.otherElements["appearanceAccentSection"]
        XCTAssertTrue(modeSection.waitForExistence(timeout: 5))
        XCTAssertTrue(accentSection.waitForExistence(timeout: 5))
        assertHorizontallyAligned(accentSection, with: modeSection, message: "模式和颜色分组应同宽")

        let textureSection = app.otherElements["appearanceTextureSection"]
        scrollUntilVisible(textureSection, app: app)
        XCTAssertTrue(textureSection.waitForExistence(timeout: 5))
        assertHorizontallyAligned(textureSection, with: modeSection, message: "网格分组应和模式分组同宽")

        let imageSection = app.otherElements["appearanceImageDisplaySection"]
        scrollUntilVisible(imageSection, app: app)
        XCTAssertTrue(imageSection.waitForExistence(timeout: 5))
        assertHorizontallyAligned(imageSection, with: modeSection, message: "图片分组应和模式分组同宽")
    }

    /// 模式区是当前主题总览：切主色时，同一张模式卡内的 FAB/强调色预览应同步重绘。
    func testSwitchingAccentColorUpdatesModeOverviewPreviewRendering() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        let darkOption = app.buttons["appearanceModeOption-dark"]
        XCTAssertTrue(darkOption.waitForExistence(timeout: 5))
        let colorBeforeSwitch = averageColor(of: darkOption)

        let greenOption = app.buttons["appearanceAccentOption-green"]
        XCTAssertTrue(greenOption.waitForExistence(timeout: 5))
        greenOption.tap()

        XCTAssertTrue(greenOption.isSelected)
        let colorAfterSwitch = averageColor(of: darkOption)
        XCTAssertTrue(
            colorDistance(colorBeforeSwitch, colorAfterSwitch) > 0.015,
            "切主色后同一张模式总览卡应同步更新 FAB/强调色预览"
        )
    }

    /// 切**模式**（暗→亮）→ 立即生效：`AppearanceThemeView` 选中态随之切换；当前主色槽位
    /// （选中的仍是同一个 `AccentColorOption`）不因切模式而改变——只是该主色解析出的具体
    /// RGB 值随模式切到其亮/暗两态（05 §5.3.2），这与「心情色随模式切换」是同一层语义
    /// （见 `MoodPaletteTests`），但主色/模式与心情色是两套独立状态，互不影响。
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

        lightOption.tap()

        XCTAssertTrue(lightOption.isSelected, "切模式应立即生效")
        XCTAssertFalse(darkOption.isSelected)

        let violetOption = app.buttons["appearanceAccentOption-violet"]
        scrollUntilVisible(violetOption, app: app)
        XCTAssertTrue(violetOption.waitForExistence(timeout: 5))
        XCTAssertTrue(violetOption.isSelected, "切模式不应改变当前选中的主色槽位（仍是紫罗兰）")
    }

    /// 任务容器的系统 row 必须跟随 `ThemeManager.mode`，不能出现 token 已是暗色但 `List`
    /// row 仍由系统浅色 scheme 渲染的混搭。
    func testTaskContainerRowsFollowModeWhileSheetIsMounted() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let appearanceRow = app.buttons["settingsAppearanceRow"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            brightness(of: appearanceRow),
            0.55,
            "默认暗色下设置页分组 row 应为暗色任务面板，不能是系统白色 row"
        )
        appearanceRow.tap()

        let darkOption = app.buttons["appearanceModeOption-dark"]
        let lightOption = app.buttons["appearanceModeOption-light"]
        XCTAssertTrue(darkOption.waitForExistence(timeout: 5))
        XCTAssertTrue(lightOption.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            brightness(of: darkOption),
            0.55,
            "默认暗色下外观页模式 row 应为暗色任务面板"
        )

        lightOption.tap()

        XCTAssertTrue(lightOption.isSelected)
        XCTAssertGreaterThan(
            brightness(of: lightOption),
            0.70,
            "切到亮色后已挂载外观页 row 应即时切到浅色任务面板"
        )
    }

    /// 外观页模式总览卡消费同一套主题 token：暗/亮两张卡应稳定呈现可见差异。
    func testSwitchingModeUpdatesModeOptionCardRendering() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        let darkOption = app.buttons["appearanceModeOption-dark"]
        XCTAssertTrue(darkOption.waitForExistence(timeout: 5))
        let colorBeforeSwitch = averageColor(of: darkOption)

        let lightOption = app.buttons["appearanceModeOption-light"]
        XCTAssertTrue(lightOption.waitForExistence(timeout: 5))
        lightOption.tap()

        XCTAssertTrue(lightOption.isSelected)
        let colorAfterSwitch = averageColor(of: lightOption)
        XCTAssertTrue(
            colorDistance(colorBeforeSwitch, colorAfterSwitch) > 0.12,
            "切模式后外观页模式缩略卡应同步变化"
        )
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
        scrollUntilVisible(gridOption, app: app)
        XCTAssertTrue(gridOption.waitForExistence(timeout: 5))
        XCTAssertTrue(dotOption.waitForExistence(timeout: 5))
        XCTAssertTrue(gridOption.isSelected, "默认背景纹理应为网格线")

        dotOption.tap()

        XCTAssertTrue(dotOption.isSelected)
        XCTAssertFalse(gridOption.isSelected)
    }

    /// 自定义背景图走设置闭环：从外观页注入图片后选中态立即切到「自定义图片」；
    /// 关闭设置回到首页后，主场景背景渲染应有可见变化。热力图上下文也属于首页主场景，
    /// 展开后仍应继承同一背景语义。
    func testInjectingCustomBackgroundImageSelectsCustomTextureAndChangesHomeBackground() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestBackgroundImageInjection"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        let colorBeforeInjection = averageColor(of: app)

        openAppearanceThemeView(app)

        let customOption = app.buttons["appearanceTextureOption-customImage"]
        scrollUntilVisible(customOption, app: app)
        XCTAssertTrue(customOption.waitForExistence(timeout: 5))

        let injectButton = app.buttons["appearanceCustomBackgroundInjectButton"]
        scrollUntilVisible(injectButton, app: app)
        XCTAssertTrue(injectButton.waitForExistence(timeout: 5))
        injectButton.tap()

        XCTAssertTrue(waitUntilSelected(customOption), "注入自定义背景图后应立即选中自定义图片")

        closeSettings(app)

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 5))
        let colorAfterInjection = averageColor(of: app)
        XCTAssertTrue(
            colorDistance(colorBeforeInjection, colorAfterInjection) > 0.05,
            "自定义背景图应改变首页主场景背景渲染"
        )

        app.buttons["年度心情热力图"].tap()
        XCTAssertTrue(app.buttons["heatmapCloseButton"].waitForExistence(timeout: 5))
        let colorWithHeatmapExpanded = averageColor(of: app)
        XCTAssertTrue(
            colorDistance(colorBeforeInjection, colorWithHeatmapExpanded) > 0.05,
            "热力图上下文展开后仍应继承首页主场景背景"
        )
    }

    /// 切图片展示方式（滚动→轮播）即时生效：选中态立即切换，无需保存按钮。
    func testSwitchingImageDisplayModeUpdatesSelectionImmediately() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openAppearanceThemeView(app)

        // 「图片」分组在页面末尾，需先滚动到底。
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

    /// 在 `AppearanceThemeView` 内下滑到底，使末尾分组（「图片」）进入可见区域。
    private func scrollToBottom(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeUp() }
    }

    private func scrollUntilVisible(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }

    private func assertHorizontallyAligned(
        _ lhs: XCUIElement,
        with rhs: XCUIElement,
        tolerance: CGFloat = 1.5,
        message: String
    ) {
        XCTAssertEqual(lhs.frame.minX, rhs.frame.minX, accuracy: tolerance, message)
        XCTAssertEqual(lhs.frame.maxX, rhs.frame.maxX, accuracy: tolerance, message)
    }

    private func closeSettings(_ app: XCUIApplication) {
        // 外观主题是设置栈内的子页，需先返回设置根页，再使用系统下滑关闭设置 sheet。
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        dismissSettingsSheet(
            app,
            from: app.buttons["settingsAppearanceRow"],
            expectedHomeButtonLabel: "新建时刻"
        )
    }

    private func waitUntilSelected(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isSelected == true")
        let selectionExpectation = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [selectionExpectation], timeout: timeout) == .completed
    }

    /// 对给定元素截屏并取整体平均颜色（`CIAreaAverage`，避免猜测单点像素坐标/字节序）。
    private func averageColor(of element: XCUIElement) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let image = element.screenshot().image
        guard let ciImage = CIImage(image: image) else { return (0, 0, 0) }
        let extent = CIVector(
            x: ciImage.extent.origin.x,
            y: ciImage.extent.origin.y,
            z: ciImage.extent.size.width,
            w: ciImage.extent.size.height
        )
        let parameters = [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: extent,
        ]
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: parameters),
            let output = filter.outputImage
        else {
            return (0, 0, 0)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return (CGFloat(bitmap[0]) / 255, CGFloat(bitmap[1]) / 255, CGFloat(bitmap[2]) / 255)
    }

    private func brightness(of element: XCUIElement) -> CGFloat {
        let color = averageColor(of: element)
        return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
    }

    /// 归一化欧氏距离（0...约1.73），用于判断两次采样的颜色是否有「明显」差异。
    private func colorDistance(
        _ lhs: (r: CGFloat, g: CGFloat, b: CGFloat),
        _ rhs: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) -> CGFloat {
        let dr = lhs.r - rhs.r
        let dg = lhs.g - rhs.g
        let db = lhs.b - rhs.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
