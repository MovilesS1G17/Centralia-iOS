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
    func testLibraryLoadsAndFiltersSavedShorts() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Continue with Apple"].tap()

        XCTAssertTrue(app.staticTexts["Search your library"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Tiny studio ideas"].exists)
        XCTAssertTrue(app.staticTexts["Three color rules"].exists)

        let libraryScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        libraryScreenshot.name = "Screen 3 - Library"
        libraryScreenshot.lifetime = .keepAlways
        add(libraryScreenshot)

        app.buttons["Reels"].tap()

        XCTAssertTrue(app.staticTexts["Three color rules"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Tiny studio ideas"].exists)
    }

    @MainActor
    func testSearchUpdatesResultsWhileTyping() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        app.tabBars.buttons["Search"].tap()

        XCTAssertTrue(app.staticTexts["Shorts in your library"].waitForExistence(timeout: 3))

        let searchField = app.textFields["globalSearchField"]
        XCTAssertTrue(searchField.exists)
        searchField.tap()
        searchField.typeText("swift")

        XCTAssertTrue(app.staticTexts["Smoother SwiftUI transitions"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Tiny studio ideas"].exists)

        let searchScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        searchScreenshot.name = "Screen 4 - Global Search"
        searchScreenshot.lifetime = .keepAlways
        add(searchScreenshot)
    }

    @MainActor
    func testSaveVideoAnalyzesAndPersistsAnUnorganizedShort() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        app.tabBars.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Save Short Video"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["addVideoTagButton"].exists)
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).count,
            0
        )

        let sourceURL = "https://www.youtube.com/shorts/\(UUID().uuidString)"
        let urlField = app.textFields["saveVideoURLField"]
        XCTAssertTrue(urlField.exists)
        urlField.tap()
        urlField.typeText(sourceURL)

        let status = app.descendants(matching: .any)["saveVideoImportStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        let detected = NSPredicate(format: "label CONTAINS %@", "YouTube Short detected")
        expectation(for: detected, evaluatedWith: status)
        waitForExpectations(timeout: 6)

        app.buttons["saveVideoFolderPicker"].tap()
        XCTAssertTrue(app.buttons["Unorganized"].waitForExistence(timeout: 2))
        app.buttons["Unorganized"].tap()

        app.swipeUp()
        let formScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        formScreenshot.name = "Screen 5 - Analyzed Video Form"
        formScreenshot.lifetime = .keepAlways
        add(formScreenshot)

        let organizedSaveButton = app.buttons["saveVideoButton"]
        XCTAssertTrue(organizedSaveButton.waitForExistence(timeout: 2))
        organizedSaveButton.tap()
        XCTAssertTrue(
            app.staticTexts["Error: Select a folder before saving."]
                .waitForExistence(timeout: 2)
        )

        let saveButton = app.buttons["saveVideoUnorganizedButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Video saved"].waitForExistence(timeout: 3))

        let saveScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        saveScreenshot.name = "Screen 5 - Save Short Video"
        saveScreenshot.lifetime = .keepAlways
        add(saveScreenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
