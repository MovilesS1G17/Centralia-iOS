import Foundation
import Testing
@testable import Centralia

@MainActor
struct TagCatalogTests {
    @Test func normalizeTrimsDropsBlanksAndDuplicatesIgnoringCase() {
        let result = TagCatalog.normalize(["  Cooking ", "cooking", "", "   ", "Travel", "TRAVEL", "Food"])
        #expect(result == ["Cooking", "Travel", "Food"])
    }

    @Test func normalizeCapsTagLength() {
        let long = String(repeating: "a", count: 90)
        #expect(TagCatalog.normalize([long]).first?.count == TagCatalog.maximumLength)
    }

    @Test func availableTagsAreDerivedFromVideosAndSorted() {
        let videos = [
            LibraryFixtures.video(url: "https://www.tiktok.com/@a/video/1", tags: ["travel", " Food "]),
            LibraryFixtures.video(url: "https://www.tiktok.com/@a/video/2", tags: ["FOOD", "art"])
        ]
        #expect(TagCatalog.available(from: videos) == ["art", "Food", "travel"])
    }

    @Test func availableTagsAreEmptyWithoutVideos() {
        #expect(TagCatalog.available(from: []).isEmpty)
    }
}

@MainActor
struct VideoSearchTests {
    private let folderA = UUID()
    private let folderB = UUID()

    private var videos: [VideoItem] {
        [
            LibraryFixtures.video(
                url: "https://www.tiktok.com/@chef/video/1",
                creator: "@chef",
                caption: "Quick pasta dinner",
                customTitle: "Weeknight pasta",
                folderID: folderA,
                tags: ["Food", "Italian"]
            ),
            LibraryFixtures.video(
                url: "https://www.instagram.com/reel/abc/",
                platform: .instagramReel,
                creator: "@traveler",
                transcript: "We landed in Lisbon after sunrise",
                folderID: folderB,
                tags: ["travel"]
            ),
            LibraryFixtures.video(
                url: "https://www.youtube.com/shorts/xyz",
                platform: .youtubeShort,
                creator: "@maker",
                caption: "Café tour",
                tags: ["food", "travel"]
            )
        ]
    }

    private func creators(_ criteria: VideoSearchCriteria) -> [String] {
        VideoSearch.filter(videos, criteria: criteria).map(\.creator)
    }

    @Test func emptyCriteriaReturnsEverything() {
        #expect(creators(VideoSearchCriteria()).count == 3)
    }

    @Test func matchesCustomTitleCaptionCreatorTranscriptAndTags() {
        #expect(creators(.init(text: "weeknight")) == ["@chef"])
        #expect(creators(.init(text: "tour")) == ["@maker"])
        #expect(creators(.init(text: "traveler")) == ["@traveler"])
        #expect(creators(.init(text: "lisbon")) == ["@traveler"])
        #expect(creators(.init(text: "italian")) == ["@chef"])
    }

    @Test func multipleTermsMustAllMatch() {
        #expect(creators(.init(text: "pasta italian")) == ["@chef"])
        #expect(creators(.init(text: "pasta lisbon")).isEmpty)
    }

    @Test func textIgnoresCaseAndDiacritics() {
        #expect(creators(.init(text: "CAFE")) == ["@maker"])
        #expect(creators(.init(text: "  lisbon  ")) == ["@traveler"])
    }

    @Test func filtersByPlatform() {
        #expect(creators(.init(platform: .instagramReel)) == ["@traveler"])
    }

    @Test func filtersByFolder() {
        #expect(creators(.init(folder: .folder(folderA))) == ["@chef"])
        #expect(creators(.init(folder: .unorganized)) == ["@maker"])
        #expect(creators(.init(folder: .all)).count == 3)
    }

    @Test func tagsRequireEveryTagIgnoringCase() {
        #expect(creators(.init(tags: ["FOOD"])).count == 2)
        #expect(creators(.init(tags: ["food", "Travel"])) == ["@maker"])
        #expect(creators(.init(tags: ["missing"])).isEmpty)
    }

    @Test func combinesTextAndFilters() {
        #expect(creators(.init(text: "food", platform: .youtubeShort)).isEmpty == false)
        #expect(creators(.init(text: "pasta", platform: .youtubeShort)).isEmpty)
    }

    @Test func folderNameIsSearchable() {
        let result = VideoSearch.filter(
            videos,
            criteria: .init(text: "recipes"),
            folderNames: [folderA: "Recipes"]
        )
        #expect(result.map(\.creator) == ["@chef"])
    }
}

@MainActor
struct AnalyticsEventTests {
    private let namePattern = /^[a-z][a-z0-9_]{1,63}$/

    @Test func eventNamesFollowTheV3Contract() {
        let id = UUID()
        let events: [AnalyticsEvent] = [
            .screenViewed(.videoDetail),
            .errorShown(screen: .library, code: "video_not_found"),
            .playStarted(videoID: id, platform: .tiktok),
            .playFailed(videoID: id, platform: .youtubeShort, reason: "open_failed"),
            .shareTapped(videoID: id)
        ]
        for event in events {
            #expect(event.name.wholeMatch(of: namePattern) != nil)
            #expect(event.properties.count <= 20)
        }
        #expect(events.map(\.name) == [
            "screen_viewed", "error_shown", "play_started", "play_failed", "share_tapped"
        ])
    }

    @Test func serverRecordedEventsAreNeverBuilt() {
        let serverEvents: Set<String> = [
            "video_saved", "video_opened", "video_updated", "video_deleted",
            "video_restored", "search_performed", "playback_requested"
        ]
        let id = UUID()
        let names = [
            AnalyticsEvent.screenViewed(.search).name,
            AnalyticsEvent.errorShown(screen: .search, code: "x").name,
            AnalyticsEvent.playStarted(videoID: id, platform: .tiktok).name,
            AnalyticsEvent.playFailed(videoID: id, platform: .tiktok, reason: "x").name,
            AnalyticsEvent.shareTapped(videoID: id).name
        ]
        #expect(serverEvents.isDisjoint(with: names))
    }

    @Test func propertiesUseTheDocumentedKeys() {
        let id = UUID()
        #expect(AnalyticsEvent.screenViewed(.folderDetail).properties == ["screen": "folder_detail"])
        #expect(AnalyticsEvent.errorShown(screen: .saveVideo, code: "duplicate_video").properties
            == ["screen": "save_video", "code": "duplicate_video"])
        #expect(AnalyticsEvent.playFailed(videoID: id, platform: .instagramReel, reason: "r").properties
            == [
                "video_id": .string(id.uuidString.lowercased()),
                "video_platform": "instagramReel",
                "reason": "r"
            ])
    }
}

@MainActor
struct FeatureErrorTests {
    @Test func usesTheBackendDetailAsTheMessage() {
        #expect(FeatureError.message(for: V3APIError.videoNotFound) == "This short is no longer in your library.")
        #expect(FeatureError.message(for: VideoItemRepositoryError.duplicateVideo)
            == "This short is already in your Centralia library.")
    }

    @Test func networkAndUnknownErrorsGetFriendlyMessages() {
        #expect(FeatureError.message(for: URLError(.notConnectedToInternet)) == FeatureError.offlineMessage)
        struct Opaque: Error {}
        #expect(FeatureError.message(for: Opaque()) == FeatureError.genericMessage)
    }

    @Test func onlyNetworkAndServerErrorsAreRetryable() {
        struct Opaque: Error {}
        #expect(FeatureError.isRetryable(URLError(.timedOut)))
        #expect(FeatureError.isRetryable(Opaque()))
        #expect(FeatureError.isRetryable(V3APIError(code: "stream_unavailable", detail: "x")))
        #expect(!FeatureError.isRetryable(VideoItemRepositoryError.duplicateVideo))
        #expect(!FeatureError.isRetryable(FolderRepositoryError.folderNotFound))
        #expect(!FeatureError.isRetryable(VideoImportError.invalidURL))
        #expect(!FeatureError.isRetryable(VideoImportError.unsupportedSource))
        #expect(!FeatureError.isRetryable(VideoImportError.unsupportedYouTubeVideo))
        #expect(!FeatureError.isRetryable(VideoImportError.unsupportedInstagramPost))
    }

    @Test func mapsKnownErrorsToV3Codes() {
        #expect(FeatureError.code(for: V3APIError.videoNotFound) == "video_not_found")
        #expect(FeatureError.code(for: VideoItemRepositoryError.duplicateVideo) == "duplicate_video")
        #expect(FeatureError.code(for: FolderRepositoryError.duplicateName) == "folder_name_duplicate")
        #expect(FeatureError.code(for: FolderRepositoryError.folderNotFound) == "folder_not_found")
        #expect(FeatureError.code(for: VideoImportError.unsupportedSource) == "unsupported_source")
        #expect(FeatureError.code(for: URLError(.timedOut)) == "network_unavailable")
    }
}

@MainActor
struct LibraryScreenStateTests {
    @Test func libraryLoadsEmptyThenShowsVideos() async {
        let library = V3SimulatedLibrary()
        let viewModel = LibraryViewModel(videoRepository: library, folderRepository: library)

        #expect(viewModel.state == .idle)
        await viewModel.load()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.isLibraryEmpty)

        library.storedVideos = [LibraryFixtures.video()]
        await viewModel.retry()
        #expect(viewModel.videos.count == 1)
        #expect(!viewModel.isLibraryEmpty)
    }

    @Test func libraryLoadFailureIsReportedAndRecoverable() async {
        let library = V3SimulatedLibrary()
        library.listError = URLError(.notConnectedToInternet)
        let analytics = RecordingAnalyticsTracking()
        let viewModel = LibraryViewModel(
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )

        await viewModel.load()
        #expect(viewModel.state == .failed(FeatureError.offlineMessage))
        #expect(analytics.events(named: "error_shown").first?.properties["code"] == "network_unavailable")

        library.listError = nil
        await viewModel.retry()
        #expect(viewModel.state == .loaded)
    }

    @Test func failedDeleteKeepsTheListAndShowsTheBackendDetail() async {
        let video = LibraryFixtures.video()
        let library = V3SimulatedLibrary(videos: [video])
        let analytics = RecordingAnalyticsTracking()
        let viewModel = LibraryViewModel(
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )
        await viewModel.load()

        library.mutationError = V3APIError.videoNotFound
        await viewModel.delete(video)

        #expect(viewModel.state == .loaded)
        #expect(viewModel.videos.count == 1)
        #expect(viewModel.failureMessage == "This short is no longer in your library.")
        #expect(analytics.events(named: "error_shown").first?.properties["code"] == "video_not_found")
    }

    @Test func screenViewedIsSentOnce() {
        let library = V3SimulatedLibrary()
        let analytics = RecordingAnalyticsTracking()
        let viewModel = LibraryViewModel(
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )
        viewModel.trackScreenViewed()
        viewModel.trackScreenViewed()
        #expect(analytics.events(named: "screen_viewed").count == 1)
    }
}

@MainActor
struct SearchScreenStateTests {
    private final class History: SearchHistoryRepository {
        var queries: [String] = []
        var error: Error?
        func recentSearches() async throws -> [String] {
            if let error { throw error }
            return queries
        }
        func recordSearch(_ query: String) async throws {
            if let error { throw error }
            queries.append(query)
        }
        func clearSearchHistory() async throws { queries = [] }
    }

    @Test func searchFiltersOnTheClientAndDerivesTags() async {
        let folder = LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")
        let library = V3SimulatedLibrary(
            videos: [
                LibraryFixtures.video(
                    url: "https://www.tiktok.com/@a/video/1",
                    creator: "@chef",
                    folderID: folder.id,
                    tags: ["Food"]
                ),
                LibraryFixtures.video(
                    url: "https://www.tiktok.com/@b/video/2",
                    creator: "@other",
                    tags: ["food", "Art"]
                )
            ],
            folders: [folder]
        )
        let viewModel = SearchViewModel(
            videoRepository: library,
            folderRepository: library,
            searchHistoryRepository: History()
        )
        await viewModel.load()

        #expect(viewModel.availableTags == ["Art", "Food"])
        viewModel.query = "recipes"
        #expect(viewModel.filteredVideos.map(\.creator) == ["@chef"])
        viewModel.query = ""
        viewModel.selectedTags = ["art"]
        #expect(viewModel.filteredVideos.map(\.creator) == ["@other"])
    }

    @Test func historyFailureDoesNotReplaceTheResults() async {
        let library = V3SimulatedLibrary(videos: [LibraryFixtures.video()])
        let history = History()
        let viewModel = SearchViewModel(
            videoRepository: library,
            folderRepository: library,
            searchHistoryRepository: history
        )
        await viewModel.load()

        history.error = V3APIError(code: "not_authenticated", detail: "Your session has ended. Please sign in again.")
        viewModel.query = "maker"
        await viewModel.submitSearch()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.failureMessage == "Your session has ended. Please sign in again.")
    }
}

@MainActor
struct FoldersAndDetailStateTests {
    @Test func duplicateFolderNameShowsTheBackendMessageAndReportsTheCode() async {
        let library = V3SimulatedLibrary(
            folders: [LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")]
        )
        let analytics = RecordingAnalyticsTracking()
        let viewModel = FoldersViewModel(
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )
        await viewModel.load()

        let created = await viewModel.createFolder(named: "recipes", symbol: .folder)

        #expect(created == nil)
        #expect(viewModel.failureMessage == "A folder with that name already exists.")
        #expect(analytics.events(named: "error_shown").first?.properties
            == ["screen": "folders", "code": "folder_name_duplicate"])
    }

    @Test func foldersScreenShowsEmptyAndErrorStates() async {
        let library = V3SimulatedLibrary()
        let viewModel = FoldersViewModel(videoRepository: library, folderRepository: library)
        await viewModel.load()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.folders.isEmpty)

        library.listError = V3APIError(code: "not_authenticated", detail: "Your session has ended. Please sign in again.")
        await viewModel.retry()
        #expect(viewModel.state == .failed("Your session has ended. Please sign in again."))
    }

    @Test func folderDetailReportsFolderNotFoundWhenMovingToADeletedFolder() async {
        let folder = LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")
        let video = LibraryFixtures.video(folderID: folder.id)
        let library = V3SimulatedLibrary(videos: [video], folders: [folder])
        let analytics = RecordingAnalyticsTracking()
        let viewModel = FolderDetailViewModel(
            folder: folder,
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )
        await viewModel.load()
        #expect(viewModel.videos.count == 1)

        await viewModel.move(video, to: UUID())

        #expect(viewModel.failureMessage == "This folder is no longer available.")
        #expect(analytics.events(named: "error_shown").first?.properties["code"] == "folder_not_found")
    }

    @Test func folderDetailSearchUsesTheSharedSearch() async {
        let folder = LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")
        let library = V3SimulatedLibrary(
            videos: [
                LibraryFixtures.video(
                    url: "https://www.tiktok.com/@a/video/1",
                    transcript: "whisk the eggs",
                    folderID: folder.id
                ),
                LibraryFixtures.video(url: "https://www.tiktok.com/@a/video/2", folderID: folder.id)
            ],
            folders: [folder]
        )
        let viewModel = FolderDetailViewModel(
            folder: folder,
            videoRepository: library,
            folderRepository: library
        )
        await viewModel.load()
        viewModel.query = "whisk"
        #expect(viewModel.filteredVideos.count == 1)
    }

    @Test func detailKeepsTheSavedCopyWhenRefreshFails() async {
        let video = LibraryFixtures.video()
        let library = V3SimulatedLibrary(videos: [video])
        library.listError = URLError(.timedOut)
        let viewModel = VideoDetailViewModel(
            video: video,
            videoRepository: library,
            folderRepository: library
        )

        await viewModel.load()

        #expect(viewModel.video == video)
        #expect(viewModel.loadFailureMessage == FeatureError.offlineMessage)
    }

    @Test func detailReportsVideoNotFoundOnUpdate() async {
        let video = LibraryFixtures.video()
        let library = V3SimulatedLibrary(videos: [])
        let analytics = RecordingAnalyticsTracking()
        let viewModel = VideoDetailViewModel(
            video: video,
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )

        let updated = await viewModel.updateTags(["a"])

        #expect(!updated)
        #expect(viewModel.failureMessage == "This short is no longer in your library.")
        #expect(analytics.events(named: "error_shown").first?.properties
            == ["screen": "video_detail", "code": "video_not_found"])
    }

    @Test func failingToOpenTheSourceEmitsOnlyPlayFailed() {
        let video = LibraryFixtures.video(platform: .instagramReel)
        let library = V3SimulatedLibrary(videos: [video])
        let analytics = RecordingAnalyticsTracking()
        let viewModel = VideoDetailViewModel(
            video: video,
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )

        viewModel.trackPlayFailed(reason: "open_failed")

        #expect(analytics.events.map(\.name) == ["play_failed"])
        #expect(analytics.events.first?.properties == [
            "video_id": .string(video.id.uuidString.lowercased()),
            "video_platform": "instagramReel",
            "reason": "open_failed"
        ])
        #expect(analytics.events(named: "play_started").isEmpty)
    }

    @Test func detailNormalizesTagsLikeTheServer() async {
        let video = LibraryFixtures.video()
        let library = V3SimulatedLibrary(videos: [video])
        let viewModel = VideoDetailViewModel(
            video: video,
            videoRepository: library,
            folderRepository: library
        )

        _ = await viewModel.updateTags([" Food ", "food", "Art"])

        #expect(viewModel.video.tags == ["Food", "Art"])
        #expect(viewModel.availableTags == ["Art", "Food"])
    }
}

@MainActor
struct SaveScreenStateTests {
    private func viewModel(
        _ library: V3SimulatedLibrary,
        analytics: RecordingAnalyticsTracking = RecordingAnalyticsTracking()
    ) -> SaveVideoViewModel {
        SaveVideoViewModel(
            pipeline: library,
            videoRepository: library,
            folderRepository: library,
            analytics: analytics
        )
    }

    @Test func unsupportedSourceFailsTheAnalysisWithTheBackendMessage() async {
        let library = V3SimulatedLibrary()
        library.importError = VideoImportError.unsupportedSource
        let analytics = RecordingAnalyticsTracking()
        let model = viewModel(library, analytics: analytics)
        model.urlText = "https://vimeo.com/1"

        await model.analyzeURL(after: .zero)

        #expect(model.analysisState == .failed(VideoImportError.unsupportedSource.localizedDescription))
        #expect(!model.canSave)
        #expect(analytics.events(named: "error_shown").first?.properties["code"] == "unsupported_source")
    }

    @Test func savingAnExistingLinkReportsDuplicateVideo() async {
        let library = V3SimulatedLibrary()
        library.storedVideos = [LibraryFixtures.video(url: library.importedMetadata.sourceURL.absoluteString)]
        let analytics = RecordingAnalyticsTracking()
        let model = viewModel(library, analytics: analytics)
        model.urlText = library.importedMetadata.sourceURL.absoluteString
        await model.analyzeURL(after: .zero)
        #expect(model.analysisState == .ready)

        let saved = await model.save(organized: false)

        #expect(saved == nil)
        #expect(model.saveFailureMessage == "This short is already in your Centralia library.")
        #expect(!model.saveFailureIsRetryable)
        #expect(analytics.events(named: "error_shown").first?.properties
            == ["screen": "save_video", "code": "duplicate_video"])
        #expect(analytics.events(named: "video_saved").isEmpty)
    }

    @Test func savingIntoAMissingFolderReportsFolderNotFound() async {
        let library = V3SimulatedLibrary()
        let model = viewModel(library)
        model.urlText = library.importedMetadata.sourceURL.absoluteString
        await model.analyzeURL(after: .zero)
        model.selectedFolderID = UUID()

        let saved = await model.save(organized: true)

        #expect(saved == nil)
        #expect(model.saveFailureMessage == "This folder is no longer available.")
    }

    @Test func transientSaveFailureIsRetryableAndKeepsTheOrganizedChoice() async {
        let library = V3SimulatedLibrary()
        let model = viewModel(library)
        model.urlText = library.importedMetadata.sourceURL.absoluteString
        await model.analyzeURL(after: .zero)
        library.saveError = URLError(.notConnectedToInternet)

        let saved = await model.save(organized: false)

        #expect(saved == nil)
        #expect(model.saveFailureIsRetryable)
        #expect(!model.lastSaveWasOrganized)
    }

    @Test func successfulSaveReturnsTheVideoWithNormalizedTags() async {
        let library = V3SimulatedLibrary()
        let model = viewModel(library)
        model.urlText = library.importedMetadata.sourceURL.absoluteString
        await model.analyzeURL(after: .zero)
        model.addTag(" Food ")
        model.addTag("food")

        let saved = await model.save(organized: false)

        #expect(saved?.tags == ["Food"])
        #expect(library.storedVideos.count == 1)
        #expect(model.saveFailureMessage == nil)
    }

    @Test func folderCreationErrorsAreSurfaced() async {
        let library = V3SimulatedLibrary(
            folders: [LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")]
        )
        let model = viewModel(library)

        let created = await model.createFolder(named: "RECIPES")

        #expect(created == nil)
        #expect(model.folderFailureMessage == "A folder with that name already exists.")
    }
}
