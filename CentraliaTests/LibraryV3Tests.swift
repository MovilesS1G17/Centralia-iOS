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
        let events: [ClientAnalyticsEvent] = [
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
            ClientAnalyticsEvent.screenViewed(.search).name,
            ClientAnalyticsEvent.errorShown(screen: .search, code: "x").name,
            ClientAnalyticsEvent.playStarted(videoID: id, platform: .tiktok).name,
            ClientAnalyticsEvent.playFailed(videoID: id, platform: .tiktok, reason: "x").name,
            ClientAnalyticsEvent.shareTapped(videoID: id).name
        ]
        #expect(serverEvents.isDisjoint(with: names))
    }

    @Test func propertiesUseTheDocumentedKeys() {
        let id = UUID()
        #expect(ClientAnalyticsEvent.screenViewed(.folderDetail).flatProperties == ["screen": "folder_detail"])
        #expect(ClientAnalyticsEvent.errorShown(screen: .saveVideo, code: "duplicate_video").flatProperties
            == ["screen": "save_video", "code": "duplicate_video"])
        #expect(ClientAnalyticsEvent.playFailed(videoID: id, platform: .instagramReel, reason: "r").flatProperties
            == [
                "video_id": id.uuidString.lowercased(),
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
        #expect(analytics.events(named: "error_shown").first?.flatProperties["code"] == "network_unavailable")

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
        #expect(analytics.events(named: "error_shown").first?.flatProperties["code"] == "video_not_found")
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

    @Test func historyFailureDoesNotBlockTheScreen() async {
        let library = V3SimulatedLibrary(videos: [LibraryFixtures.video()])
        let history = History()
        history.error = V3APIError(code: "not_authenticated", detail: "Your session has ended. Please sign in again.")
        let viewModel = SearchViewModel(
            videoRepository: library,
            folderRepository: library,
            searchHistoryRepository: history
        )

        await viewModel.load()
        viewModel.query = "maker"
        await viewModel.submitSearch()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.failureMessage == nil)
        #expect(viewModel.recentSearches.isEmpty)
        #expect(viewModel.videos.count == 1)
    }

    @Test func submittedSearchesAreRecordedAndListed() async {
        let library = V3SimulatedLibrary(videos: [LibraryFixtures.video()])
        let history = History()
        let viewModel = SearchViewModel(
            videoRepository: library,
            folderRepository: library,
            searchHistoryRepository: history
        )
        await viewModel.load()

        viewModel.query = "  pasta  "
        await viewModel.submitSearch()

        #expect(history.queries == ["pasta"])
        #expect(viewModel.recentSearches == ["pasta"])

        await viewModel.clearRecentSearches()
        #expect(viewModel.recentSearches.isEmpty)
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
        #expect(analytics.events(named: "error_shown").first?.flatProperties
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
        #expect(analytics.events(named: "error_shown").first?.flatProperties["code"] == "folder_not_found")
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
        #expect(analytics.events(named: "error_shown").first?.flatProperties
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

        viewModel.trackPlayFailedOpeningSource()

        #expect(analytics.events.map(\.name) == ["play_failed"])
        #expect(analytics.events.first?.flatProperties == [
            "video_id": video.id.uuidString.lowercased(),
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
        #expect(analytics.events(named: "error_shown").first?.flatProperties["code"] == "unsupported_source")
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
        #expect(analytics.events(named: "error_shown").first?.flatProperties
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

@MainActor
struct VideoPlaybackTests {
    private func makeViewModel(
        _ result: Result<VideoPlayback, Error>?,
        analytics: RecordingAnalyticsTracking = RecordingAnalyticsTracking()
    ) -> (VideoDetailViewModel, ScriptedPlaybackRepository?, VideoItem) {
        let video = LibraryFixtures.video()
        let library = V3SimulatedLibrary(videos: [video])
        let playback = result.map(ScriptedPlaybackRepository.init)
        let viewModel = VideoDetailViewModel(
            video: video,
            videoRepository: library,
            folderRepository: library,
            playbackRepository: playback,
            analytics: analytics
        )
        return (viewModel, playback, video)
    }

    private let stream = URL(string: "https://api.example.com/v1/streams/1?expires=1&signature=a")!
    private let embed = URL(string: "https://www.tiktok.com/embed/v2/1")!

    @Test func withoutARepositoryThePreviewStaysStatic() async {
        let (viewModel, _, _) = makeViewModel(nil)
        #expect(!viewModel.supportsPlayback)
        await viewModel.startPlayback()
        #expect(viewModel.playbackState == .idle)
    }

    @Test func streamIsPreferredAndStartsPlayback() async {
        let analytics = RecordingAnalyticsTracking()
        let (viewModel, repository, video) = makeViewModel(
            .success(VideoPlayback(streamURL: stream, streamReady: true, expiresAt: nil, embedURL: embed)),
            analytics: analytics
        )

        await viewModel.startPlayback()

        #expect(viewModel.playbackState == .ready(.stream(stream)))
        #expect(repository?.requestedIDs == [video.id])
        #expect(analytics.events.map(\.name) == ["play_started"])
    }

    @Test func embedIsUsedWhenThereIsNoStream() async {
        let (viewModel, _, _) = makeViewModel(
            .success(VideoPlayback(streamURL: nil, streamReady: false, expiresAt: nil, embedURL: embed))
        )
        await viewModel.startPlayback()
        #expect(viewModel.playbackState == .ready(.embed(embed)))
    }

    @Test func failedStreamFallsBackToTheEmbedAndReportsTheFailure() async {
        let analytics = RecordingAnalyticsTracking()
        let (viewModel, _, _) = makeViewModel(
            .success(VideoPlayback(streamURL: stream, streamReady: true, expiresAt: nil, embedURL: embed)),
            analytics: analytics
        )
        await viewModel.startPlayback()

        viewModel.streamFailed()

        #expect(viewModel.playbackState == .ready(.embed(embed)))
        #expect(analytics.events.map(\.name) == ["play_started", "play_failed"])
        #expect(analytics.events.last?.flatProperties["reason"] == "stream_failed")
    }

    @Test func failedStreamWithoutEmbedShowsAnError() async {
        let (viewModel, _, _) = makeViewModel(
            .success(VideoPlayback(streamURL: stream, streamReady: true, expiresAt: nil, embedURL: nil))
        )
        await viewModel.startPlayback()
        viewModel.streamFailed()
        #expect(viewModel.playbackState == .failed(VideoDetailViewModel.playbackUnavailableMessage))
    }

    @Test func insecureEmbedIsNotUsed() async {
        let analytics = RecordingAnalyticsTracking()
        let (viewModel, _, _) = makeViewModel(
            .success(VideoPlayback(
                streamURL: nil, streamReady: false, expiresAt: nil,
                embedURL: URL(string: "http://example.com/embed")
            )),
            analytics: analytics
        )

        await viewModel.startPlayback()

        #expect(viewModel.playbackState == .failed(VideoDetailViewModel.playbackUnavailableMessage))
        #expect(analytics.events.first?.flatProperties["reason"] == "playback_unavailable")
    }

    @Test func backendErrorShowsItsDetailAndReportsPlayFailed() async {
        let analytics = RecordingAnalyticsTracking()
        let (viewModel, _, _) = makeViewModel(
            .failure(V3APIError.server("video_not_found", "This short is no longer in your library.")),
            analytics: analytics
        )

        await viewModel.startPlayback()

        #expect(viewModel.playbackState == .failed("This short is no longer in your library."))
        #expect(analytics.events.map(\.name) == ["play_failed"])
        #expect(analytics.events.first?.flatProperties["reason"] == "video_not_found")
    }

    @Test func insecureStreamIsIgnoredAndTheEmbedIsUsed() async {
        let (viewModel, _, _) = makeViewModel(
            .success(VideoPlayback(
                streamURL: URL(string: "http://example.com/v1/streams/1"),
                streamReady: true, expiresAt: nil, embedURL: embed
            ))
        )

        await viewModel.startPlayback()

        #expect(viewModel.playbackState == .ready(.embed(embed)))
    }

    @Test func embedFailureEndsInAnError() async {
        let analytics = RecordingAnalyticsTracking()
        let (viewModel, _, _) = makeViewModel(
            .success(VideoPlayback(streamURL: nil, streamReady: false, expiresAt: nil, embedURL: embed)),
            analytics: analytics
        )
        await viewModel.startPlayback()

        viewModel.embedFailed()

        #expect(viewModel.playbackState == .failed(VideoDetailViewModel.playbackUnavailableMessage))
        #expect(analytics.events.last?.flatProperties["reason"] == "embed_failed")
    }

    @Test func playbackCanBeRetriedAndClosed() async {
        let (viewModel, repository, _) = makeViewModel(.failure(URLError(.notConnectedToInternet)))
        await viewModel.startPlayback()
        #expect(viewModel.playbackState == .failed(FeatureError.offlineMessage))

        repository?.result = .success(VideoPlayback(streamURL: nil, streamReady: false, expiresAt: nil, embedURL: embed))
        await viewModel.startPlayback()
        #expect(viewModel.playbackState == .ready(.embed(embed)))

        viewModel.stopPlayback()
        #expect(viewModel.playbackState == .idle)
    }
}

@MainActor
struct ImportFlowTests {
    private func model(_ library: V3SimulatedLibrary) -> SaveVideoViewModel {
        let model = SaveVideoViewModel(pipeline: library, videoRepository: library, folderRepository: library)
        model.urlText = library.importedMetadata.sourceURL.absoluteString
        return model
    }

    @Test func fullFlowFillsSuggestionsAndSavesTheVideo() async {
        let folder = LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")
        let library = V3SimulatedLibrary(folders: [folder])
        library.suggestedTags = ["food", " Food ", "quick"]
        library.suggestedFolderName = "recipes"
        let model = model(library)
        await model.loadFolders()

        await model.analyzeURL(after: .zero)

        #expect(model.analysisState == .ready)
        #expect(model.suggestedTags == ["food", "quick"])
        #expect(model.selectedFolderID == folder.id)

        let saved = await model.save(organized: true)
        #expect(saved?.folderID == folder.id)
        #expect(library.storedVideos.count == 1)
    }

    @Test func tagAndFolderSuggestionFailuresDoNotBlockSaving() async {
        let library = V3SimulatedLibrary()
        library.tagsError = URLError(.timedOut)
        library.suggestionError = URLError(.timedOut)
        let model = model(library)

        await model.analyzeURL(after: .zero)

        #expect(model.analysisState == .ready)
        #expect(model.suggestedTags.isEmpty)
        #expect(model.suggestedFolderName == nil)
        #expect(model.canSave)
    }

    @Test func linkErrorsAreShownWithTheBackendMessageAndAreNotRetryable() async {
        let cases: [(Error, String)] = [
            (VideoImportError.invalidURL, "invalid_url"),
            (VideoImportError.unsupportedSource, "unsupported_source"),
            (VideoImportError.unsupportedYouTubeVideo, "unsupported_youtube_video"),
            (VideoImportError.unsupportedInstagramPost, "unsupported_instagram_post"),
            (V3APIError.server("unsupported_source", "Centralia currently supports TikTok videos only."),
             "unsupported_source")
        ]

        for (error, code) in cases {
            let library = V3SimulatedLibrary()
            library.importError = error
            let analytics = RecordingAnalyticsTracking()
            let model = SaveVideoViewModel(
                pipeline: library, videoRepository: library, folderRepository: library, analytics: analytics
            )
            model.urlText = "https://example.com/video"

            await model.analyzeURL(after: .zero)

            #expect(model.analysisState == .failed(error.localizedDescription))
            #expect(!model.canSave)
            #expect(!FeatureError.isRetryable(error))
            #expect(analytics.events(named: "error_shown").first?.flatProperties["code"] == code)
        }
    }

    @Test func duplicateVideoFromTheServerIsNotRetryable() async {
        let library = V3SimulatedLibrary()
        let model = model(library)
        await model.analyzeURL(after: .zero)
        library.saveError = V3APIError.server("duplicate_video", "This short is already in your Centralia library.")

        let saved = await model.save(organized: false)

        #expect(saved == nil)
        #expect(model.saveFailureMessage == "This short is already in your Centralia library.")
        #expect(!model.saveFailureIsRetryable)
    }
}

@MainActor
struct FolderManagementTests {
    private let folder = LibraryFolder(id: UUID(), name: "Recipes", symbolName: "folder")

    private func detail(_ library: V3SimulatedLibrary) -> FolderDetailViewModel {
        FolderDetailViewModel(folder: folder, videoRepository: library, folderRepository: library)
    }

    @Test func renameSucceedsAndUpdatesTheFolder() async {
        let library = V3SimulatedLibrary(folders: [folder])
        let model = detail(library)

        let renamed = await model.renameFolder(to: "  Dinner ")

        #expect(renamed)
        #expect(model.folder.name == "Dinner")
    }

    @Test func renameRejectsEmptyAndDuplicateNames() async {
        let other = LibraryFolder(id: UUID(), name: "Travel", symbolName: "folder")
        let library = V3SimulatedLibrary(folders: [folder, other])
        let model = detail(library)

        #expect(await model.renameFolder(to: "   ") == false)
        #expect(model.failureMessage == "Enter a folder name.")

        #expect(await model.renameFolder(to: "travel") == false)
        #expect(model.failureMessage == "A folder with that name already exists.")
        #expect(model.folder.name == "Recipes")
    }

    @Test func renamingAMissingFolderReportsFolderNotFound() async {
        let library = V3SimulatedLibrary(folders: [])
        let analytics = RecordingAnalyticsTracking()
        let model = FolderDetailViewModel(
            folder: folder, videoRepository: library, folderRepository: library, analytics: analytics
        )

        #expect(await model.renameFolder(to: "Dinner") == false)
        #expect(model.failureMessage == "This folder is no longer available.")
        #expect(analytics.events(named: "error_shown").first?.flatProperties["code"] == "folder_not_found")
    }

    @Test func deleteMovesVideosToUnorganizedAndReportsSuccess() async {
        let video = LibraryFixtures.video(folderID: folder.id)
        let library = V3SimulatedLibrary(videos: [video], folders: [folder])
        let model = detail(library)

        #expect(await model.deleteFolder())
        #expect(library.storedFolders.isEmpty)
        #expect(library.storedVideos.first?.folderID == nil)
    }

    @Test func deletingAFolderThatIsAlreadyGoneCountsAsDone() async {
        let library = V3SimulatedLibrary(folders: [])
        let model = detail(library)

        #expect(await model.deleteFolder())
        #expect(model.failureMessage == nil)
    }

    @Test func otherDeleteFailuresAreShown() async {
        let library = V3SimulatedLibrary(folders: [folder])
        library.folderError = URLError(.notConnectedToInternet)
        let model = detail(library)

        #expect(await model.deleteFolder() == false)
        #expect(model.failureMessage == FeatureError.offlineMessage)
    }
}

@MainActor
struct BatchingAnalyticsTrackerTests {
    private func event(_ screen: AnalyticsScreen = .library) -> ClientAnalyticsEvent {
        .screenViewed(screen)
    }

    @Test func flushSendsBufferedEventsInOneBatch() async {
        let repository = RecordingAnalyticsRepository()
        let tracker = BatchingAnalyticsTracker(repository: repository, batchSize: 50, flushInterval: .seconds(60))

        tracker.track(event())
        tracker.track(event(.search))
        #expect(tracker.pendingCount == 2)
        #expect(repository.batches.isEmpty)

        await tracker.flush()

        #expect(repository.batches.map(\.count) == [2])
        #expect(tracker.pendingCount == 0)
    }

    @Test func reachingTheBatchSizeSendsWithoutWaiting() async {
        let repository = RecordingAnalyticsRepository()
        let tracker = BatchingAnalyticsTracker(repository: repository, batchSize: 3, flushInterval: .seconds(60))

        for _ in 0..<3 { tracker.track(event()) }

        for _ in 0..<100 where repository.batches.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(repository.batches.map(\.count) == [3])
    }

    @Test func bufferedEventsAreSentAfterTheFlushInterval() async {
        let repository = RecordingAnalyticsRepository()
        let tracker = BatchingAnalyticsTracker(repository: repository, batchSize: 50, flushInterval: .milliseconds(30))

        tracker.track(event())

        for _ in 0..<100 where repository.batches.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(repository.batches.map(\.count) == [1])
    }

    @Test func failedSendKeepsTheEventsForTheNextAttempt() async {
        let repository = RecordingAnalyticsRepository()
        repository.error = URLError(.notConnectedToInternet)
        let tracker = BatchingAnalyticsTracker(repository: repository, batchSize: 50, flushInterval: .seconds(60))
        tracker.track(event())

        await tracker.flush()
        #expect(tracker.pendingCount == 1)

        repository.error = nil
        await tracker.flush()
        #expect(repository.batches.map(\.count) == [1])
        #expect(tracker.pendingCount == 0)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func noBatchExceedsTheServerLimit() async {
        let repository = GatedAnalyticsRepository()
        let tracker = BatchingAnalyticsTracker(
            repository: repository, batchSize: 100, flushInterval: .seconds(60), maxBuffered: 250
        )

        // The first batch stays in flight while 150 more events pile up.
        for _ in 0..<100 { tracker.track(event()) }
        await waitUntil { repository.callsStarted == 1 }
        for _ in 0..<150 { tracker.track(event()) }
        #expect(tracker.pendingCount == 150)

        repository.isBlocking = false
        await waitUntil { repository.batches.reduce(0) { $0 + $1.count } == 250 }

        #expect(repository.batches.map(\.count) == [100, 100, 50])
        #expect(repository.batches.allSatisfy { $0.count <= BatchingAnalyticsTracker.maximumBatchSize })
        #expect(tracker.pendingCount == 0)
    }

    @Test func oldestEventsAreDroppedWhenTheBufferIsFull() async {
        let repository = GatedAnalyticsRepository()
        let tracker = BatchingAnalyticsTracker(
            repository: repository, batchSize: 10, flushInterval: .seconds(60), maxBuffered: 20
        )
        func numbered(_ index: Int) -> ClientAnalyticsEvent {
            .errorShown(screen: .library, code: "n\(index)")
        }

        for index in 0..<10 { tracker.track(numbered(index)) }
        await waitUntil { repository.callsStarted == 1 }

        // 25 more events with room for 20: the 5 oldest are dropped.
        for index in 10..<35 { tracker.track(numbered(index)) }
        #expect(tracker.pendingCount == 20)

        repository.isBlocking = false
        await waitUntil { repository.batches.reduce(0) { $0 + $1.count } == 30 }

        let sentCodes = repository.batches.flatMap { $0.map { $0.flatProperties["code"] ?? "" } }
        #expect(repository.batches.map(\.count) == [10, 20])
        #expect(sentCodes == (0..<10).map { "n\($0)" } + (15..<35).map { "n\($0)" })
    }

    @Test func failedSendRetriesOnItsOwnWithoutAnotherEvent() async {
        let repository = RecordingAnalyticsRepository()
        repository.error = URLError(.notConnectedToInternet)
        let tracker = BatchingAnalyticsTracker(
            repository: repository,
            batchSize: 50,
            flushInterval: .seconds(60),
            retryBaseDelay: .milliseconds(20),
            maxRetryDelay: .milliseconds(80)
        )
        tracker.track(event())

        await tracker.flush()
        #expect(tracker.pendingCount == 1)
        #expect(repository.batches.isEmpty)

        // The endpoint recovers; no new event and no explicit flush.
        repository.error = nil
        await waitUntil { !repository.batches.isEmpty }

        #expect(repository.batches.map(\.count) == [1])
        #expect(tracker.pendingCount == 0)
    }

    @Test func retryDelayGrowsAndIsCapped() {
        let base = Duration.seconds(2)
        let maximum = Duration.seconds(60)
        let delays = (0..<8).map {
            BatchingAnalyticsTracker.retryDelay(forAttempt: $0, base: base, maximum: maximum)
        }
        #expect(delays == [
            .seconds(2), .seconds(4), .seconds(8), .seconds(16),
            .seconds(32), .seconds(60), .seconds(60), .seconds(60)
        ])
        #expect(BatchingAnalyticsTracker.retryDelay(forAttempt: 500, base: base, maximum: maximum) == maximum)
    }
}

@MainActor
struct PlaybackURLPolicyTests {
    private func allowed(_ text: String, local: Bool) -> Bool {
        PlaybackURLPolicy.isAllowed(URL(string: text)!, allowLocalHTTP: local)
    }

    @Test func httpsIsAlwaysAllowed() {
        #expect(allowed("https://api.example.com/v1/streams/1", local: false))
        #expect(allowed("https://www.tiktok.com/embed/v2/1", local: true))
    }

    @Test func otherSchemesAreRejected() {
        for text in ["ftp://example.com/a", "file:///etc/hosts", "javascript:alert(1)", "data:text/html,hi"] {
            #expect(!allowed(text, local: true))
            #expect(!allowed(text, local: false))
        }
    }

    @Test func httpToTheInternetIsRejectedEvenWhenLocalHTTPIsOn() {
        #expect(!allowed("http://example.com/embed", local: true))
        #expect(!allowed("http://example.com/embed", local: false))
        #expect(!allowed("http://192.168.1.10.example.com/embed", local: true))
    }

    @Test func httpToLocalHostsIsOnlyAllowedWhenEnabled() {
        let hosts = [
            "http://localhost:8000/v1/streams/1", "http://127.0.0.1:8000/x", "http://10.0.0.5/x",
            "http://172.16.0.1/x", "http://172.31.255.255/x", "http://192.168.0.20/x",
            "http://mac.local:8000/x", "http://[::1]:8000/x"
        ]
        for text in hosts {
            #expect(allowed(text, local: true))
            #expect(!allowed(text, local: false))
        }
    }

    @Test func publicAddressesAreNotLocal() {
        for text in ["http://172.32.0.1/x", "http://172.15.0.1/x", "http://8.8.8.8/x", "http://11.0.0.1/x"] {
            #expect(!allowed(text, local: true))
        }
    }
}
