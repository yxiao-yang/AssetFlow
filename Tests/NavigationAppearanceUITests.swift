import XCTest

final class NavigationAppearanceUITests: XCTestCase {
    private func launch(settings: Bool = false, screenshot: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.modest.AssetFlow.Regression")
        app.launchArguments = ["--demo-ledger"] + (settings ? ["--demo-settings"] : [])
            + (screenshot ? ["--demo-pending-image"] : [])
        app.launch()
        return app
    }

    private func expectAppearance(_ app: XCUIApplication, light: Bool) {
        let matches = NSPredicate { _, _ in
            guard let image = app.screenshot().image.cgImage,
                  let data = image.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else { return false }
            let x = image.width / 100, y = image.height * 3 / 10
            let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
            let brightness = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            return light ? brightness > 200 : brightness < 150
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: nil)], timeout: 8)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = light ? "Expected light appearance" : "Expected dark appearance"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed, "The currently presented settings page did not update its appearance")
    }

    func testFollowSystemLight() {
        let app = launch(settings: true)
        XCTAssertTrue(app.staticTexts["夜间模式"].waitForExistence(timeout: 10))
        app.staticTexts["夜间模式"].tap()
        expectAppearance(app, light: false)
        app.staticTexts["跟随系统"].tap()
        expectAppearance(app, light: true)
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["资产流"].waitForExistence(timeout: 5))
    }

    func testFollowSystemDark() {
        let app = launch(settings: true)
        XCTAssertTrue(app.staticTexts["白天模式"].waitForExistence(timeout: 10))
        app.staticTexts["白天模式"].tap()
        expectAppearance(app, light: true)
        app.staticTexts["跟随系统"].tap()
        expectAppearance(app, light: false)
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["资产流"].waitForExistence(timeout: 5))
    }

    func testPendingNavigationAndDeleteLast() {
        let app = launch(screenshot: true)
        XCTAssertTrue(app.staticTexts["1 笔截图待确认"].waitForExistence(timeout: 10))
        for _ in 0..<3 {
            app.staticTexts["1 笔截图待确认"].tap()
            XCTAssertTrue(app.staticTexts["截图待确认"].waitForExistence(timeout: 5))
            app.staticTexts["截图待确认"].tap()
            XCTAssertTrue(app.staticTexts["分类（可修改）"].waitForExistence(timeout: 5))
            for _ in 0..<8 {
                if app.buttons["删除记录"].isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(app.buttons["删除记录"].isHittable)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["截图待确认"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["1 笔截图待确认"].waitForExistence(timeout: 5))
        }
        app.staticTexts["1 笔截图待确认"].tap()
        app.staticTexts["截图待确认"].tap()
        for _ in 0..<8 {
            if app.buttons["删除记录"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["删除记录"].isHittable)
        app.buttons["删除记录"].tap()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.navigationBars["资产流"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["1 笔截图待确认"].exists)
        app.tabBars.buttons["图表"].tap()
        XCTAssertTrue(app.navigationBars["收支分析"].waitForExistence(timeout: 5))
    }
}
