import XCTest

final class CentraliaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignUpAndLogInNavigation() throws {
        let app = makeApp()
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
        let app = makeApp()
        app.launch()

        app.buttons["Continue with email"].tap()
        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: 2))
        app.buttons["Create account"].tap()

        XCTAssertTrue(app.staticTexts["Error: Enter a valid email address."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Error: Use at least 8 characters, with letters and numbers."].exists)
    }

    @MainActor
    func testPasswordResetRemainsReadableWithAccessibilityText() throws {
        let app = makeApp()
        useAccessibilityText(in: app)
        app.launch()

        app.buttons["Log In"].tap()
        app.buttons["Forgot password?"].tap()

        let sheet = app.scrollViews["passwordResetForm"]
        let email = sheet.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 3))
        email.tap()
        email.typeText("reader@example.com\n")

        let code = sheet.textFields["Verification code"]
        XCTAssertTrue(code.waitForExistence(timeout: 3))
        let reset = sheet.buttons["Reset password"]
        for _ in 0..<8 where !reset.isHittable {
            sheet.swipeUp()
        }
        XCTAssertTrue(reset.isHittable)
        reset.tap()
        let error = sheet.staticTexts["Error: Use at least 8 characters, with letters and numbers."]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        capture("Password reset with accessibility text")
    }

    @MainActor
    func testLibraryLoadsAndFiltersSavedShorts() throws {
        let app = makeApp()
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
        let app = makeApp()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        let searchTab = app.tabBars.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 5))
        searchTab.tap()

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
    func testSavedSearchSurvivesRelaunchAndReappliesFiltersOffline() {
        let app = makeApp()
        app.launchEnvironment["CENTRALIA_UI_TEST_DATA_ID"] = UUID().uuidString
        app.launch()

        func openSearch() {
            app.buttons["Continue with Apple"].tap()
            let searchTab = app.buttons["Search"].firstMatch
            XCTAssertTrue(searchTab.waitForExistence(timeout: 8))
            searchTab.tap()
            XCTAssertTrue(app.staticTexts["Shorts in your library"].waitForExistence(timeout: 4))
        }

        openSearch()
        let field = app.textFields["globalSearchField"]
        field.tap()
        field.typeText("ceramics")
        app.buttons["Platform filter"].tap()
        app.buttons["Instagram Reel"].tap()
        app.buttons["Folder filter"].tap()
        app.buttons["Design"].tap()
        app.buttons["saveCurrentSearch"].tap()

        let name = app.textFields["savedSearchName"]
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        XCTAssertEqual(name.value as? String, "ceramics")
        app.buttons["commitSavedSearchName"].tap()

        let savedRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'applySavedSearch.'")).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 4))
        XCTAssertTrue(savedRow.label.contains("ceramics"))
        capture("Saved Searches")

        app.terminate()
        app.launchArguments += ["--offline-ui-testing"]
        app.launch()
        openSearch()
        XCTAssertTrue(app.staticTexts["You're offline. Showing your saved library."].exists)
        XCTAssertEqual(app.buttons["Platform filter"].value as? String, "All platforms")
        app.buttons["openSavedSearches"].tap()
        XCTAssertTrue(savedRow.waitForExistence(timeout: 4))

        app.buttons["Actions for ceramics"].tap()
        app.buttons["Rename"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 4))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "ceramics".count))
        name.typeText("Workshop")
        app.buttons["commitSavedSearchName"].tap()
        XCTAssertTrue(savedRow.waitForExistence(timeout: 4))
        XCTAssertTrue(savedRow.label.contains("Workshop"))
        savedRow.tap()

        XCTAssertTrue(app.staticTexts["Centering clay on the wheel"].waitForExistence(timeout: 4))
        XCTAssertEqual(field.value as? String, "ceramics")
        XCTAssertEqual(app.buttons["Platform filter"].value as? String, "Instagram Reel")
        XCTAssertEqual(app.buttons["Folder filter"].value as? String, "Design")
        XCTAssertFalse(app.staticTexts["Three color rules"].exists)
        capture("Saved search applied after offline relaunch")
    }

    @MainActor
    func testBatchImportSavesValidLinksAndPreservesTheSingleLinkDraft() {
        let app = makeApp()
        app.launch()
        app.buttons["Continue with Apple"].tap()

        let saveTab = app.buttons["Save"].firstMatch
        XCTAssertTrue(saveTab.waitForExistence(timeout: 8))
        saveTab.tap()
        let singleLink = app.textFields["saveVideoURLField"]
        XCTAssertTrue(singleLink.waitForExistence(timeout: 4))
        let originalDraft = "https://www.youtube.com/shorts/individual"
        singleLink.tap()
        singleLink.typeText(originalDraft)
        app.buttons["openBatchImport"].tap()

        let input = app.textViews["batchImportLinks"]
        XCTAssertTrue(input.waitForExistence(timeout: 4))
        input.tap()
        input.typeText("https://www.youtube.com/shorts/batchone\ninvalid\nhttps://www.instagram.com/reel/batchtwo")
        app.buttons["batchImportCheck"].tap()

        let save = app.buttons["batchImportSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 6))
        XCTAssertEqual(save.label, "Save 2 to Unorganized")
        let invalid = app.descendants(matching: .any)["batchImportRow.1"]
        XCTAssertTrue(invalid.label.contains("Enter a complete link"))
        capture("Batch import review")
        save.tap()

        let done = app.buttons["batchImportDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["batchImportSavedCount"].label, "2 saved to Unorganized")
        capture("Batch import complete")
        done.tap()
        XCTAssertTrue(singleLink.waitForExistence(timeout: 4))
        XCTAssertEqual(singleLink.value as? String, originalDraft)
    }

    @MainActor
    func testSaveVideoAnalyzesAndPersistsAnUnorganizedShort() throws {
        let app = makeApp()
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
        let app = makeApp()
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
    func testNewFolderAppearsInTheEmptyLibraryAndCanReceiveAShort() throws {
        let app = makeApp()
        app.launchArguments += ["--empty-library", "--folder-sync-ui-testing"]
        app.launch()

        app.buttons["Continue with Apple"].tap()
        let saveShort = app.buttons["Save a Short"]
        XCTAssertTrue(saveShort.waitForExistence(timeout: 5))
        XCTAssertTrue(saveShort.isHittable)
        XCTAssertFalse(app.buttons["New Folder"].exists)
        capture("Empty library actions")

        saveShort.tap()
        XCTAssertTrue(app.staticTexts["Save Short Video"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()

        app.tabBars.buttons["Folders"].tap()
        let newFolderButton = app.buttons["newFolderButton"]
        XCTAssertTrue(newFolderButton.waitForExistence(timeout: 3))
        XCTAssertTrue(newFolderButton.isHittable)
        XCTAssertTrue(app.staticTexts["Create your first folder"].waitForExistence(timeout: 3))
        capture("Empty folders actions")

        newFolderButton.tap()
        let folderName = "First folder"
        let nameField = app.textFields["newFolderNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(folderName)
        app.buttons["saveNewFolderButton"].tap()

        let createdFolder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", folderName)
        ).firstMatch
        XCTAssertTrue(createdFolder.waitForExistence(timeout: 3))

        app.tabBars.buttons["Library"].tap()
        let shortcut = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", folderName)).firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 3))
        XCTAssertTrue(shortcut.label.contains("0 shorts"))

        app.tabBars.buttons["Save"].tap()
        app.buttons["saveVideoFolderPicker"].tap()
        let destination = app.buttons[folderName]
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        destination.tap()

        let urlField = app.textFields["saveVideoURLField"]
        urlField.tap()
        urlField.typeText("https://www.youtube.com/shorts/new-folder-test")
        let saveVideo = app.buttons["saveVideoButton"]
        app.swipeUp()
        let isEnabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: saveVideo)
        XCTAssertEqual(XCTWaiter.wait(for: [isEnabled], timeout: 6), .completed)
        saveVideo.tap()
        XCTAssertTrue(app.staticTexts[folderName].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        XCTAssertTrue(shortcut.label.contains("1 short"))

        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["More video actions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFoldersCreatesAndOpensAFolderDetail() throws {
        let app = makeApp()
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
        XCTAssertTrue(app.buttons["folderDetailSort"].exists)
        XCTAssertTrue(app.buttons["folderDetailTags"].exists)

        let foldersScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        foldersScreenshot.name = "Screens 8 and 9 - Folders and Folder Detail"
        foldersScreenshot.lifetime = .keepAlways
        add(foldersScreenshot)
    }

    @MainActor
    func testOfflineFolderRenameSurvivesRelaunchAndSyncsWhenOnline() {
        let app = makeApp()
        app.launchEnvironment["CENTRALIA_UI_TEST_DATA_ID"] = UUID().uuidString
        app.launchArguments += ["--folder-sync-ui-testing"]

        func openFolder(named name: String) {
            app.buttons["Continue with Apple"].tap()
            let folders = app.buttons["Folders"].firstMatch
            XCTAssertTrue(folders.waitForExistence(timeout: 8))
            folders.tap()
            let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),")).firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout: 8))
            folder.tap()
            XCTAssertTrue(app.buttons["folderDetailSort"].waitForExistence(timeout: 5))
        }

        app.launch()
        openFolder(named: "Design")
        app.terminate()

        let newName = "Studio Offline"
        app.launchArguments += ["--offline-ui-testing"]
        app.launch()
        openFolder(named: "Design")
        app.buttons["folderDetailMoreActions"].tap()
        app.buttons["Rename Folder"].tap()
        let name = app.textFields["renameFolderNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Design".count))
        name.typeText(newName)
        app.buttons["saveFolderRename"].tap()

        let pending = app.staticTexts["folderRenamePending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts[newName].exists)
        capture("Folder rename pending offline")
        app.terminate()

        app.launch()
        openFolder(named: newName)
        XCTAssertTrue(pending.waitForExistence(timeout: 4))
        app.terminate()

        app.launchArguments.removeAll { $0 == "--offline-ui-testing" }
        app.launch()
        openFolder(named: newName)
        let noPending = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: noPending, object: pending)], timeout: 6), .completed)
        XCTAssertTrue(app.staticTexts[newName].exists)
        capture("Folder rename synchronized")
    }

    @MainActor
    func testFolderPDFCanBePreviewedAndShared() {
        let app = makeApp()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        let foldersTab = app.buttons["Folders"].firstMatch
        XCTAssertTrue(foldersTab.waitForExistence(timeout: 8))
        foldersTab.tap()

        let designFolder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Design'")).firstMatch
        XCTAssertTrue(designFolder.waitForExistence(timeout: 5))
        designFolder.tap()
        XCTAssertTrue(app.buttons["folderDetailSort"].waitForExistence(timeout: 5))
        app.buttons["folderDetailMoreActions"].tap()
        app.buttons["Export Folder as PDF"].tap()

        let preview = app.buttons["folderPDFPreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        capture("Folder PDF ready")
        preview.tap()
        XCTAssertTrue(app.navigationBars["Folder PDF"].waitForExistence(timeout: 5))
        capture("Folder PDF preview")

        app.buttons["Done"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let share = app.buttons["folderPDFShare"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let sharedFilename = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Centralia - Design"))
            .firstMatch
        XCTAssertTrue(sharedFilename.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Save to Files"].exists)
        capture("Folder PDF share sheet")
    }

    @MainActor
    func testFolderDetailSearchSortAndTagsStayInsideCurrentFolder() throws {
        let app = makeApp()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        app.tabBars.buttons["Folders"].tap()

        let designFolder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Design'")
        ).firstMatch
        XCTAssertTrue(designFolder.waitForExistence(timeout: 3))
        designFolder.tap()

        let searchField = app.textFields["folderDetailSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("ceramics")

        XCTAssertTrue(
            app.staticTexts["Centering clay on the wheel"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts["Three color rules"].exists)

        app.buttons["folderDetailClearSearch"].tap()
        app.buttons["folderDetailSort"].tap()
        XCTAssertTrue(app.buttons["Alphabetical"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Date Saved"].exists)
        app.buttons["Alphabetical"].tap()

        app.buttons["folderDetailTags"].tap()
        XCTAssertTrue(app.navigationBars["Filter by Tags"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["color"].exists)
        XCTAssertTrue(app.buttons["ceramics"].exists)
        XCTAssertFalse(app.buttons["studio"].exists)

        app.buttons["color"].tap()
        app.navigationBars["Filter by Tags"].buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Three color rules"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Centering clay on the wheel"].exists)

        let detailScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailScreenshot.name = "Screen 9 - Folder Detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    @MainActor
    func testFolderSuggestionsComeFromCacheAfterOfflineRelaunch() {
        let app = makeApp()
        app.launchEnvironment["CENTRALIA_UI_TEST_DATA_ID"] = UUID().uuidString
        func openUnorganized() {
            app.buttons["Continue with Apple"].tap()
            let folders = app.buttons["Folders"].firstMatch
            XCTAssertTrue(folders.waitForExistence(timeout: 8))
            folders.tap()
            let unorganized = app.buttons["unorganizedCollection"]
            XCTAssertTrue(unorganized.waitForExistence(timeout: 6))
            unorganized.tap()
        }

        app.launch()
        openUnorganized()
        let pager = app.descendants(matching: .any)["smartOrganizationPager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 6))
        let refresh = app.buttons["refreshFolderSuggestions"]
        XCTAssertTrue(refresh.exists)
        let folderAction = pager.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Suggested folder ")).firstMatch
        XCTAssertTrue(folderAction.waitForExistence(timeout: 4))
        let suggestedFolder = folderAction.label
        XCTAssertEqual(suggestedFolder, "Suggested folder Design. Change folder")
        app.terminate()

        app.launchArguments += ["--offline-ui-testing"]
        app.launch()
        openUnorganized()
        let cached = app.descendants(matching: .any)["savedFolderSuggestions"]
        XCTAssertTrue(cached.waitForExistence(timeout: 6))
        XCTAssertTrue(pager.exists)
        XCTAssertTrue(folderAction.waitForExistence(timeout: 4))
        XCTAssertEqual(folderAction.label, suggestedFolder)
        XCTAssertFalse(refresh.exists)
        XCTAssertTrue(app.staticTexts["You're offline. Showing your saved library."].exists)
        capture("Saved organization suggestions after offline relaunch")
    }

    @MainActor
    func testSmartOrganizationSkipKeepsTheVideoUnorganized() throws {
        let app = makeApp()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        let foldersTab = app.tabBars.buttons["Folders"]
        XCTAssertTrue(foldersTab.waitForExistence(timeout: 5))
        foldersTab.tap()

        let unorganized = app.buttons["unorganizedCollection"]
        XCTAssertTrue(unorganized.waitForExistence(timeout: 3))
        unorganized.tap()

        XCTAssertTrue(app.staticTexts["Organize"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Folders"].exists)
        let pager = app.descendants(matching: .any)["smartOrganizationPager"]
        let pageIndicator = app.descendants(matching: .any)["smartOrganizationPageIndicator"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertTrue(pageIndicator.exists)

        let count = app.staticTexts["smartOrganizationCount"]
        XCTAssertTrue(count.exists)
        let countBeforeSkip = count.label

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Screen 10 - Smart Organization"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 2))
        skip.tap()

        XCTAssertEqual(count.label, countBeforeSkip)
    }

    @MainActor
    func testSmartOrganizationCardKeepsActionsInsidePagerWithAccessibilityText() throws {
        let app = makeApp()
        useAccessibilityText(in: app)
        app.launch()

        app.buttons["Continue with Apple"].tap()
        let foldersTab = app.tabBars.buttons["Folders"]
        XCTAssertTrue(foldersTab.waitForExistence(timeout: 5))
        foldersTab.tap()
        app.buttons["unorganizedCollection"].tap()

        let pager = app.descendants(matching: .any)["smartOrganizationPager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 8))
        let skip = pager.buttons["Skip"].firstMatch
        for _ in 0..<8 where !skip.isHittable {
            app.swipeUp()
        }
        capture("Organization suggestions with accessibility text")
        XCTAssertTrue(skip.isHittable)
        XCTAssertGreaterThanOrEqual(pager.frame.maxY, skip.frame.maxY)
        skip.tap()
    }

    @MainActor
    func testProfileShowsRepositoryDataAndSignsOut() throws {
        let app = makeApp()
        app.launch()

        app.buttons["Continue with Apple"].tap()
        app.tabBars.buttons["Profile"].tap()

        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["profileIdentity"].exists)
        XCTAssertTrue(app.staticTexts["Storage Used"].exists)
        XCTAssertTrue(app.staticTexts["Your library"].exists)
        XCTAssertTrue(app.staticTexts["Saved by platform"].exists)

        app.buttons["Edit Profile"].tap()
        XCTAssertTrue(app.navigationBars["Edit Profile"].waitForExistence(timeout: 2))
        app.navigationBars["Edit Profile"].buttons["Cancel"].tap()

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Screen 11 - Profile"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let signOut = app.descendants(matching: .any)["profileSignOut"]
        signOut.tap()
        let destructiveSignOut = app.sheets.buttons["Sign Out"]
        XCTAssertTrue(destructiveSignOut.waitForExistence(timeout: 2))
        destructiveSignOut.tap()

        XCTAssertTrue(app.staticTexts["Welcome back."].waitForExistence(timeout: 4))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing"]
        return app
    }

    private func useAccessibilityText(in app: XCUIApplication) {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
