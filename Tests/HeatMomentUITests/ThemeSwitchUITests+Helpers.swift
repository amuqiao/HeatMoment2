import CoreImage
import UIKit
import XCTest

@MainActor
extension ThemeSwitchUITests {
    func openAppearanceThemeView(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let appearanceRow = app.buttons["settingsAppearanceRow"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        appearanceRow.tap()
    }

    /// 在 `AppearanceThemeView` 内下滑到底，使末尾分组（「图片」）进入可见区域。
    func scrollToBottom(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeUp() }
    }

    func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeDown() }
    }

    func scrollUntilVisible(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<6 where !element.exists || !element.isHittable {
            app.swipeUp()
        }
    }

    func scrollHorizontallyUntilVisible(
        _ element: XCUIElement,
        in scrollView: XCUIElement
    ) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        for _ in 0..<6 where !element.exists || !element.isHittable {
            scrollView.swipeLeft()
        }
    }

    func assertFeaturedBackgroundGalleryIsPure(_ app: XCUIApplication) {
        let gallery = app.scrollViews["featuredBackgroundScrollView"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        XCTAssertTrue(
            gallery.otherElements["featuredBackgroundCurrentPreview"].waitForExistence(timeout: 5))
        XCTAssertFalse(gallery.staticTexts["马上创建"].exists, "精选背景页不应混入 moment 预览标题")
        XCTAssertFalse(gallery.staticTexts["什么是时刻?"].exists, "精选背景页不应混入 moment 预览标题")
        XCTAssertFalse(gallery.staticTexts["17:06"].exists, "精选背景页不应混入时间轴日期时间预览")
    }

    func assertHorizontallyAligned(
        _ lhs: XCUIElement,
        with rhs: XCUIElement,
        tolerance: CGFloat = 1.5,
        message: String
    ) {
        XCTAssertEqual(lhs.frame.minX, rhs.frame.minX, accuracy: tolerance, message)
        XCTAssertEqual(lhs.frame.maxX, rhs.frame.maxX, accuracy: tolerance, message)
    }

    func closeSettings(_ app: XCUIApplication) {
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

    func waitUntilSelected(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isSelected == true")
        let selectionExpectation = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [selectionExpectation], timeout: timeout) == .completed
    }

    /// 对给定元素截屏并取整体平均颜色（`CIAreaAverage`，避免猜测单点像素坐标/字节序）。
    func averageColor(of element: XCUIElement) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
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

    func brightness(of element: XCUIElement) -> CGFloat {
        let color = averageColor(of: element)
        return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
    }

    /// 归一化欧氏距离（0...约1.73），用于判断两次采样的颜色是否有「明显」差异。
    func colorDistance(
        _ lhs: (r: CGFloat, g: CGFloat, b: CGFloat),
        _ rhs: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) -> CGFloat {
        let dr = lhs.r - rhs.r
        let dg = lhs.g - rhs.g
        let db = lhs.b - rhs.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
