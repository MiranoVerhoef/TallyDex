import XCTest
final class ScanLabUITests: XCTestCase {
    func testGoalsAndGenerationScreen() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.staticTexts["Your next goal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start automatic capture"].exists)
        for _ in 0..<5 { if app.buttons["Generate extras"].exists && app.buttons["Generate extras"].isHittable { break }; app.swipeUp() }
        app.buttons["Generate extras"].tap()
        XCTAssertTrue(app.staticTexts["Supplementary examples"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Generate training extras"].exists)
        app.buttons["Done"].tap()
    }
}
