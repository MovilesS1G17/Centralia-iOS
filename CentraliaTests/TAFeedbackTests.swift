import Foundation
import Testing
@testable import Centralia

/// The three app-side fixes from the TA's review (same cases as
/// `TAFeedbackTest.kt` on Android).
@MainActor
struct TAFeedbackTests {
    // "When the tag is very long the data leaves the screen": 30-character limit.
    @Test func tagFieldNeverHoldsMoreThanThirtyCharacters() {
        let typed = String(repeating: "a", count: 45)
        #expect(TagRules.limitInput(typed).count == 30)
        #expect(TagRules.limitInput("short") == "short")
        #expect(TagRules.counter("  two   words ") == "9/30")
        #expect(TagRules.isValid(String(repeating: "x", count: 30)))
        #expect(!TagRules.isValid(String(repeating: "x", count: 31)))
        #expect(!TagRules.isValid("   "))
        #expect(TagCatalog.maximumLength == 30)
    }

    // "Done should save what was just done": a typed tag is kept on Done/Save.
    @Test func pendingTagIsAddedOnceIgnoringCase() {
        #expect(TagRules.addingPending("  Meal  prep ", to: ["gym"]) == ["gym", "Meal prep"])
        #expect(TagRules.addingPending("GYM", to: ["gym"]) == ["gym"])
        #expect(TagRules.addingPending("", to: ["gym"]) == ["gym"])
    }

    @Test func doneOnTheAddTagSheetKeepsTheTypedTag() {
        // The sheet's Done calls the same view-model method as "Add Tag".
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ta-feedback-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "ta-feedback.json"
        )
        let model = SaveVideoViewModel(
            pipeline: MockVideoImportPipeline(delay: .zero),
            videoRepository: repository,
            folderRepository: repository
        )
        model.addTag(TagRules.clean("  weekend  trip "))
        #expect(model.selectedTags == ["weekend trip"])
    }

    // "When saving an inadmissible link, make it more telling".
    @Test func rejectedLinkShowsTheServerTitleAndHowToFixIt() {
        let error = APIClientError.server(
            status: 422,
            code: "unsupported_source",
            detail: "It points to a profile, not to one video. Open the video, tap Share → Copy link, and paste it here.",
            email: nil,
            retryAfter: nil,
            title: "This TikTok link isn't a video"
        )
        let problem = LinkProblem.from(error: error, message: error.localizedDescription)
        #expect(problem.title == "This TikTok link isn't a video")
        #expect(problem.message.contains("Copy link"))
    }

    @Test func rejectedLinkWithoutTitleStillGetsASpecificOne() {
        let problem = LinkProblem.from(code: "unsupported_youtube_video", title: nil, detail: "x")
        #expect(problem.title == "This is a regular YouTube video")
        #expect(LinkProblem.from(code: "nope", title: nil, detail: nil).title == LinkProblem.defaultTitle)
    }

    @Test func offlineLinkCheckSaysItIsOfflineNotUnsupported() {
        let problem = LinkProblem.from(error: APIClientError.networkUnavailable, message: "")
        #expect(problem.title == LinkProblem.offlineTitle)
    }
}
