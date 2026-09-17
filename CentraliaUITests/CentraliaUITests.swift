import XCTest

final class CentraliaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignUpAndLogInNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Save every short worth keeping."].waitForExistence(timeout: 3))
        app.buttons["Log In"].tap()

        XCTAssertTrue(app.staticTexts["Welcome back."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Forgot password?"].exists)

        app.buttons["Create account"].tap()
        XCTAssertTrue(app.staticTexts["Save every short worth keeping."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEmailSignUpShowsInlineValidation() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Continue with email"].tap()
        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: 2))
        app.buttons["Create account"].tap()

        XCTAssertTrue(app.staticTexts["Error: Enter a valid email address."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Error: Use at least 8 characters."].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
