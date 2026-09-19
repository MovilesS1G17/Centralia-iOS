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

        app.buttons["addVideoTagButton"].tap()
        let tagField = app.textFields["newTagField"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 2))
        for tag in ["swiftui-test", "motion-test", "learning-test"] {
            tagField.tap()
            tagField.typeText(tag)
            app.buttons["Add Tag"].tap()
        }
        app.navigationBars["Add tag"].buttons["Done"].tap()

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

        XCTAssertTrue(app.staticTexts["Saved to Centralia"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No Folder Select"].exists)
        XCTAssertTrue(app.staticTexts["swiftui-test"].exists)
        XCTAssertTrue(app.staticTexts["motion-test"].exists)
        XCTAssertTrue(app.staticTexts["learning-test"].exists)
        XCTAssertTrue(app.buttons["Add Note"].exists)

        app.buttons["Add Note"].tap()
        let noteField = app.textViews["confirmationNoteField"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 2))
        noteField.tap()
        noteField.typeText("Review this during the next sprint.")
        app.navigationBars["Add Note"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add Note"].waitForNonExistence(timeout: 3))

        let saveScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        saveScreenshot.name = "Screen 6 - Save Confirmation"
        saveScreenshot.lifetime = .keepAlways
        add(saveScreenshot)
    }

    @MainActor
    func testVideoDetailEditsTagsAndChangesFolderState() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        let videoMetadata = app.buttons["Tiny studio ideas, @roomreset"]
        XCTAssertTrue(videoMetadata.waitForExistence(timeout: 3))
        videoMetadata.tap()

        XCTAssertTrue(app.staticTexts["videoDetailTitle"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["videoDetailTitle"].label, "Tiny studio ideas")

        let tag = app.buttons["videoDetailTag_studio"]
        XCTAssertTrue(tag.exists)
        tag.tap()
        XCTAssertTrue(app.navigationBars["Edit Tags"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["studio"].exists)

        let newTagField = app.textFields["videoDetailNewTagField"]
        newTagField.tap()
        newTagField.typeText("detail-test")
        app.buttons["Add"].tap()
        app.buttons["videoDetailSaveTags"].tap()
        XCTAssertTrue(app.buttons["videoDetailTag_detail-test"].waitForExistence(timeout: 3))

        let folderAction = app.buttons["videoDetailFolderAction"]
        XCTAssertTrue(folderAction.exists)

        if folderAction.label == "Change Folder" {
            folderAction.tap()
            XCTAssertTrue(app.navigationBars["Move Video"].waitForExistence(timeout: 2))
            app.buttons["Unorganized"].tap()
            XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 3))
        } else {
            folderAction.tap()
            XCTAssertTrue(app.navigationBars["Move Video"].waitForExistence(timeout: 2))
            app.buttons["Spaces"].tap()
            XCTAssertTrue(app.buttons["Change Folder"].waitForExistence(timeout: 3))
        }

        let detailScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailScreenshot.name = "Screen 7 - Video Detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    @MainActor
    func testFoldersCreatesAndOpensAFolderDetail() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        app.tabBars.buttons["Folders"].tap()
        XCTAssertTrue(app.staticTexts["Folders"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["unorganizedCollection"].exists)

        let foldersSearchField = app.textFields["foldersSearchField"]
        XCTAssertTrue(foldersSearchField.waitForExistence(timeout: 2))
        foldersSearchField.tap()
        foldersSearchField.typeText("Design")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Design'"))
                .firstMatch.waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recipes'"))
                .firstMatch.exists
        )
        app.buttons["clearFoldersSearch"].tap()

        let folderName = "UI Folder \(UUID().uuidString.prefix(5))"
        app.buttons["newFolderButton"].tap()
        let folderField = app.textFields["newFolderNameField"]
        XCTAssertTrue(folderField.waitForExistence(timeout: 2))
        folderField.tap()
        folderField.typeText(folderName)
        app.buttons["folderSymbol.lightbulb"].tap()
        app.buttons["saveNewFolderButton"].tap()

        let newFolder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", folderName)
        ).firstMatch
        XCTAssertTrue(newFolder.waitForExistence(timeout: 3))
        newFolder.tap()
        XCTAssertTrue(app.textFields["folderDetailSearchField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["folderDetailFilters"].exists)

        let foldersScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        foldersScreenshot.name = "Screens 8 and 9 - Folders and Folder Detail"
        foldersScreenshot.lifetime = .keepAlways
        add(foldersScreenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
