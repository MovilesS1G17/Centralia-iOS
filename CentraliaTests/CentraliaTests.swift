import Foundation
import Testing
@testable import Centralia

struct CentraliaTests {
    @Test func authenticationValidation() {
        #expect(AuthenticationValidation.emailError(for: "person@example.com") == nil)
        #expect(AuthenticationValidation.emailError(for: "not-an-email") != nil)
        #expect(AuthenticationValidation.passwordError(for: "12345678") == nil)
        #expect(AuthenticationValidation.passwordError(for: "short") != nil)
    }

    @Test func signUpRejectsMismatchedPasswordsBeforeCallingRepository() async {
        let viewModel = SignUpViewModel(
            repository: MockAuthenticationRepository(delay: .zero)
        )
        viewModel.email = "person@example.com"
        viewModel.password = "password-one"
        viewModel.passwordConfirmation = "password-two"

        let user = await viewModel.createAccount()

        #expect(user == nil)
        #expect(viewModel.confirmationError == "Passwords do not match.")
        #expect(viewModel.isSubmittingEmail == false)
    }

    @Test func logInPreservesInputAndExposesRecoverableFailure() async {
        let viewModel = LogInViewModel(
            repository: MockAuthenticationRepository(delay: .zero)
        )
        viewModel.email = "fail@example.com"
        viewModel.password = "valid-password"

        let user = await viewModel.logIn()

        #expect(user == nil)
        #expect(viewModel.email == "fail@example.com")
        #expect(viewModel.password == "valid-password")
        #expect(viewModel.failureMessage == AuthenticationError.invalidCredentials.localizedDescription)
    }

    @Test func socialAuthenticationCompletesSession() async throws {
        let repository = MockAuthenticationRepository(delay: .zero)
        let session = AppSession()

        let user = try await repository.authenticate(with: .apple)
        session.completeAuthentication(with: user)

        #expect(session.phase == .authenticated(user))
    }

    @Test func socialAuthenticationCancellationIsRecoverable() async {
        let viewModel = SignUpViewModel(
            repository: MockAuthenticationRepository(
                delay: .zero,
                providerFailures: [.apple: .providerCancelled]
            )
        )

        let user = await viewModel.authenticate(with: .apple)

        #expect(user == nil)
        #expect(viewModel.failureMessage == AuthenticationError.providerCancelled.localizedDescription)
        #expect(viewModel.activeProvider == nil)
    }

    @Test func deterministicMockReturnsSameIdentityForSameEmail() async throws {
        let repository = MockAuthenticationRepository(delay: .zero)

        let first = try await repository.logIn(
            email: "person@example.com",
            password: "valid-password"
        )
        let second = try await repository.logIn(
            email: "person@example.com",
            password: "another-password"
        )

        #expect(first.id == second.id)
    }

    @Test func libraryFiltersVideosBySource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "library-filter-test.json"
        )
        let viewModel = LibraryViewModel(
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.load()
        #expect(viewModel.videos.count == 6)
        #expect(viewModel.filteredVideos.count == 6)

        viewModel.selectedFilter = .platform(.instagramReel)

        #expect(viewModel.filteredVideos.count == 2)
        #expect(viewModel.filteredVideos.allSatisfy { $0.platform == .instagramReel })
    }

    @Test func libraryMutationsPersistAcrossRepositoryInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let filename = "library-persistence-test.json"
        let repository = MockLibraryRepository(store: store, filename: filename)
        let originalVideos = try await repository.videos()
        let folders = try await repository.folders()

        #expect(originalVideos.count == 6)
        #expect(folders.isEmpty == false)

        guard let video = originalVideos.first, let destination = folders.first else {
            return
        }

        try await repository.moveVideo(id: video.id, to: destination.id)

        let reloadedRepository = MockLibraryRepository(store: store, filename: filename)
        let movedVideo = try await reloadedRepository.videos().first { $0.id == video.id }
        #expect(movedVideo?.folderID == destination.id)

        try await reloadedRepository.deleteVideo(id: video.id)
        #expect(try await reloadedRepository.videos().contains { $0.id == video.id } == false)

        try await reloadedRepository.restoreVideo(video)
        #expect(try await reloadedRepository.videos().contains { $0.id == video.id })
    }

    @Test func videoDetailPersistsFolderAndTagChanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let filename = "video-detail-persistence-test.json"
        let repository = MockLibraryRepository(store: store, filename: filename)
        let video = try #require(try await repository.videos().first)
        let viewModel = VideoDetailViewModel(
            video: video,
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.load()
        #expect(viewModel.folderActionTitle == "Change Folder")
        #expect(viewModel.folderName != nil)

        #expect(await viewModel.move(to: nil))
        #expect(viewModel.folderActionTitle == "Choose Folder")
        #expect(viewModel.folderName == nil)

        #expect(await viewModel.updateTags(["Swift", "Animation", "swift", "  "]))
        #expect(viewModel.video.tags == ["Swift", "Animation"])

        let reloadedRepository = MockLibraryRepository(store: store, filename: filename)
        let persistedVideo = try #require(
            try await reloadedRepository.videos().first { $0.id == video.id }
        )
        #expect(persistedVideo.folderID == nil)
        #expect(persistedVideo.tags == ["Swift", "Animation"])
    }

    @Test func videoTitleUsesTheBestAvailableSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "library-title-test.json"
        )
        var video = try await repository.videos()[0]

        #expect(video.displayTitle == video.generatedSummary)

        video.customTitle = "My saved title"
        #expect(video.displayTitle == "My saved title")
    }

    @Test func searchUpdatesResultsFromQueryAndFilters() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(
            store: store,
            filename: "search-library-test.json"
        )
        let searchHistoryRepository = MockSearchHistoryRepository(
            store: store,
            filename: "search-history-test.json"
        )
        let viewModel = SearchViewModel(
            videoRepository: libraryRepository,
            folderRepository: libraryRepository,
            searchHistoryRepository: searchHistoryRepository
        )

        await viewModel.load()
        #expect(viewModel.filteredVideos.count == 6)

        viewModel.query = "SwiftUI animation"
        #expect(viewModel.filteredVideos.map(\.displayTitle) == ["Smoother SwiftUI transitions"])

        viewModel.query = ""
        viewModel.selectedPlatform = .instagramReel
        #expect(viewModel.filteredVideos.count == 2)
        #expect(viewModel.filteredVideos.allSatisfy { $0.platform == .instagramReel })

        viewModel.selectedTags = ["design"]
        #expect(viewModel.filteredVideos.map(\.displayTitle) == ["Three color rules"])
    }

    @Test func searchDoesNotClaimTranscriptOrCaptionMatching() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(
            store: store,
            filename: "search-fields-test.json"
        )
        let viewModel = SearchViewModel(
            videoRepository: libraryRepository,
            folderRepository: libraryRepository,
            searchHistoryRepository: MockSearchHistoryRepository(
                store: store,
                filename: "search-fields-history-test.json"
            )
        )

        await viewModel.load()
        viewModel.query = "natural light"

        #expect(viewModel.filteredVideos.isEmpty)
    }

    @Test func recentSearchesPersistAndDeduplicate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let filename = "recent-searches-persistence-test.json"
        let repository = MockSearchHistoryRepository(store: store, filename: filename)

        try await repository.recordSearch("color")
        try await repository.recordSearch("pasta")
        try await repository.recordSearch("COLOR")

        let reloadedRepository = MockSearchHistoryRepository(store: store, filename: filename)
        let searches = try await reloadedRepository.recentSearches()

        #expect(searches.first == "COLOR")
        #expect(searches.count { $0.localizedCaseInsensitiveCompare("color") == .orderedSame } == 1)

        try await reloadedRepository.clearSearchHistory()
        #expect(try await reloadedRepository.recentSearches().isEmpty)
    }

    @Test func videoImportPipelineIsDeterministicAndRestrictedToShortForm() async throws {
        let pipeline = MockVideoImportPipeline(delay: .zero)
        let sourceURL = try #require(
            URL(string: "https://www.youtube.com/shorts/deterministic-example")
        )

        let platform = try await pipeline.detectPlatform(from: sourceURL)
        let first = try await pipeline.extractMetadata(from: sourceURL, platform: platform)
        let second = try await pipeline.extractMetadata(from: sourceURL, platform: platform)

        #expect(platform == .youtubeShort)
        #expect(first == second)
        #expect(try await pipeline.generateTags(for: first).isEmpty == false)
        #expect(try await pipeline.suggestFolder(for: first, tags: []) != nil)

        let longFormURL = try #require(
            URL(string: "https://www.youtube.com/watch?v=not-a-short")
        )

        do {
            _ = try await pipeline.detectPlatform(from: longFormURL)
            Issue.record("A regular YouTube video should be rejected.")
        } catch let error as VideoImportError {
            #expect(error == .unsupportedYouTubeVideo)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func saveVideoAnalysisLeavesTagsUnselected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "save-analysis-test.json"
        )
        let viewModel = SaveVideoViewModel(
            pipeline: MockVideoImportPipeline(delay: .zero),
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.loadFolders()
        viewModel.urlText = "https://www.instagram.com/reel/new-centralia-item"
        await viewModel.analyzeURL(after: .zero)

        #expect(viewModel.analysisState == .ready)
        #expect(viewModel.metadata?.platform == .instagramReel)
        #expect(viewModel.suggestedTags.isEmpty == false)
        #expect(viewModel.selectedTags.isEmpty)
        #expect(viewModel.selectedFolderID != nil)
    }

    @Test func saveWithoutOrganizingPersistsSelectedTagsAndNote() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let filename = "save-unorganized-test.json"
        let repository = MockLibraryRepository(store: store, filename: filename)
        let viewModel = SaveVideoViewModel(
            pipeline: MockVideoImportPipeline(delay: .zero),
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.loadFolders()
        viewModel.urlText = "https://www.tiktok.com/@centralia/video/new-save-test"
        await viewModel.analyzeURL(after: .zero)
        viewModel.addTag("keep-out-of-unorganized-save")
        viewModel.note = "Remember this explanation."

        let savedVideo = try #require(await viewModel.save(organized: false))
        let persistedVideo = try #require(
            try await repository.videos().first { $0.id == savedVideo.id }
        )

        #expect(persistedVideo.folderID == nil)
        #expect(persistedVideo.tags == ["keep-out-of-unorganized-save"])
        #expect(persistedVideo.note == "Remember this explanation.")
    }

    @Test func organizedSaveRequiresAFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "save-folder-validation-test.json"
        )
        let viewModel = SaveVideoViewModel(
            pipeline: MockVideoImportPipeline(delay: .zero),
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.loadFolders()
        viewModel.urlText = "https://www.youtube.com/shorts/folder-validation-test"
        await viewModel.analyzeURL(after: .zero)
        viewModel.selectedFolderID = nil

        let savedVideo = await viewModel.save(organized: true)

        #expect(savedVideo == nil)
        #expect(viewModel.folderSelectionError == "Select a folder before saving.")
        #expect(try await repository.videos().count == 6)

        viewModel.selectedFolderID = try #require(viewModel.folders.first?.id)
        #expect(viewModel.folderSelectionError == nil)
    }

    @Test func newFoldersPersistAndDuplicateVideosAreRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let filename = "save-repository-test.json"
        let repository = MockLibraryRepository(store: store, filename: filename)
        let folder = try await repository.createFolder(
            named: "Motion",
            symbolName: FolderSymbol.lightbulb.rawValue
        )

        let reloadedRepository = MockLibraryRepository(store: store, filename: filename)
        #expect(try await reloadedRepository.folders().contains(folder))
        #expect(folder.symbolName == FolderSymbol.lightbulb.rawValue)

        let video = VideoItem(
            id: UUID(),
            sourceURL: try #require(URL(string: "https://www.youtube.com/shorts/duplicate-test")),
            platform: .youtubeShort,
            creator: "@centralia",
            durationSeconds: 20,
            sourceCaption: nil,
            transcript: nil,
            extractedOnScreenText: nil,
            generatedSummary: "Duplicate example",
            customTitle: nil,
            folderID: folder.id,
            tags: [],
            note: nil,
            savedAt: Date(),
            analysisStatus: .completed
        )

        try await reloadedRepository.saveVideo(video)

        do {
            try await reloadedRepository.saveVideo(video)
            Issue.record("A duplicate source URL should not be saved twice.")
        } catch let error as VideoItemRepositoryError {
            #expect(error == .duplicateVideo)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func saveConfirmationPersistsNoteAndHidesAddNoteAction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let filename = "save-confirmation-note-test.json"
        let repository = MockLibraryRepository(store: store, filename: filename)
        let video = try #require(try await repository.videos().first { $0.note == nil })
        let viewModel = SaveConfirmationViewModel(
            video: video,
            videoRepository: repository
        )

        #expect(viewModel.shouldShowAddNote)
        #expect(await viewModel.saveNote("  Review this during the next sprint.  "))
        #expect(viewModel.shouldShowAddNote == false)
        #expect(viewModel.video.note == "Review this during the next sprint.")

        let reloadedRepository = MockLibraryRepository(store: store, filename: filename)
        let reloadedVideo = try #require(
            try await reloadedRepository.videos().first { $0.id == video.id }
        )
        #expect(reloadedVideo.note == "Review this during the next sprint.")
    }

    @Test func foldersCanBeRenamedAndDeletedWithoutDeletingTheirShorts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let repository = MockLibraryRepository(store: store, filename: "folder-crud-test.json")
        let folder = try #require(try await repository.folders().first)
        let savedInFolder = try #require(
            try await repository.videos().first { $0.folderID == folder.id }
        )

        let renamed = try await repository.renameFolder(id: folder.id, to: "Ideas")
        #expect(renamed.name == "Ideas")
        #expect(try await repository.folders().contains(renamed))

        try await repository.deleteFolder(id: folder.id)

        #expect(try await repository.folders().contains { $0.id == folder.id } == false)
        #expect(
            try await repository.videos().first { $0.id == savedInFolder.id }?.folderID == nil
        )
    }

    @Test func foldersSearchFiltersOnlyFolderNamesInRealTime() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "folders-search-test.json"
        )
        let viewModel = FoldersViewModel(
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.load()
        viewModel.query = "des"

        #expect(viewModel.filteredFolders.map(\.name) == ["Design"])

        viewModel.query = "  RECIPES  "
        #expect(viewModel.filteredFolders.map(\.name) == ["Recipes"])

        viewModel.query = ""
        #expect(viewModel.filteredFolders.count == viewModel.folders.count)
    }

    @Test func folderDetailScopesSearchFiltersAndSortToTheCurrentFolder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "folder-detail-filter-test.json"
        )
        let folder = try #require(
            try await repository.folders().first { $0.name == "Design" }
        )
        let viewModel = FolderDetailViewModel(
            folder: folder,
            videoRepository: repository,
            folderRepository: repository
        )

        await viewModel.load()
        #expect(viewModel.videos.count == 2)

        viewModel.query = "ceramics"
        #expect(viewModel.filteredVideos.map(\.displayTitle) == ["Centering clay on the wheel"])

        viewModel.query = ""
        viewModel.selectedSourceFilter = .platform(.instagramReel)
        #expect(viewModel.filteredVideos.count == 2)

        viewModel.sort = .alphabetical
        #expect(viewModel.filteredVideos.map(\.displayTitle) == [
            "Centering clay on the wheel",
            "Three color rules"
        ])

        #expect(viewModel.availableTags == [
            "ceramics", "color", "craft", "design", "tutorial", "visual identity"
        ])

        viewModel.selectedTags = ["color"]
        #expect(viewModel.filteredVideos.map(\.displayTitle) == ["Three color rules"])

        viewModel.selectedTags = []
        viewModel.sort = .dateSaved
        #expect(viewModel.filteredVideos.map(\.displayTitle) == [
            "Three color rules",
            "Centering clay on the wheel"
        ])
    }

    @Test func smartOrganizationUsesThePersistedFolderIconAndAcceptMovesTheVideo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "smart-organization-accept-test.json"
        )
        let viewModel = SmartOrganizationViewModel(
            videoRepository: repository,
            folderRepository: repository,
            suggestionPipeline: MockVideoImportPipeline(delay: .zero)
        )

        await viewModel.load()

        let suggestion = try #require(viewModel.suggestions.first)
        let persistedFolder = try #require(
            try await repository.folders().first { $0.id == suggestion.folder.id }
        )
        #expect(suggestion.folder.symbolName == persistedFolder.symbolName)
        #expect(viewModel.unorganizedCount == 1)

        #expect(await viewModel.accept(suggestion))

        let persistedVideo = try #require(
            try await repository.videos().first { $0.id == suggestion.video.id }
        )
        #expect(persistedVideo.folderID == suggestion.folder.id)
        #expect(viewModel.unorganizedCount == 0)
        #expect(viewModel.suggestions.isEmpty)
    }

    @Test func smartOrganizationSkipDismissesTheSuggestionWithoutMovingTheVideo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "smart-organization-skip-test.json"
        )
        let viewModel = SmartOrganizationViewModel(
            videoRepository: repository,
            folderRepository: repository,
            suggestionPipeline: MockVideoImportPipeline(delay: .zero)
        )

        await viewModel.load()
        let suggestion = try #require(viewModel.suggestions.first)

        viewModel.skip(suggestion)

        let persistedVideo = try #require(
            try await repository.videos().first { $0.id == suggestion.video.id }
        )
        #expect(persistedVideo.folderID == nil)
        #expect(viewModel.unorganizedCount == 1)
        #expect(viewModel.suggestions.isEmpty)
    }

    @Test func smartOrganizationSelectionTracksSwipedSuggestionsAndAdvancesAfterSkip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = MockLibraryRepository(
            store: MockDataStore(directoryURL: directory),
            filename: "smart-organization-paging-test.json"
        )
        let baseDate = Date(timeIntervalSince1970: 1_789_166_400)

        for index in 1...2 {
            try await repository.saveVideo(
                VideoItem(
                    id: UUID(),
                    sourceURL: URL(string: "https://www.tiktok.com/@centralia/video/paging-\(index)")!,
                    platform: .tiktok,
                    creator: "@centralia",
                    durationSeconds: 20 + index,
                    sourceCaption: nil,
                    transcript: nil,
                    extractedOnScreenText: nil,
                    generatedSummary: "Paging suggestion \(index)",
                    customTitle: nil,
                    folderID: nil,
                    tags: ["design"],
                    note: nil,
                    savedAt: baseDate.addingTimeInterval(Double(index)),
                    analysisStatus: .completed
                )
            )
        }

        let viewModel = SmartOrganizationViewModel(
            videoRepository: repository,
            folderRepository: repository,
            suggestionPipeline: MockVideoImportPipeline(delay: .zero)
        )
        await viewModel.load()

        #expect(viewModel.suggestions.count == 3)
        let secondSuggestion = viewModel.suggestions[1]
        viewModel.selectedSuggestionID = secondSuggestion.id
        #expect(viewModel.selectedSuggestion?.id == secondSuggestion.id)

        viewModel.skip(secondSuggestion)

        #expect(viewModel.suggestions.count == 2)
        #expect(viewModel.suggestions.contains { $0.id == secondSuggestion.id } == false)
        #expect(viewModel.selectedSuggestionID == viewModel.suggestions[1].id)
        #expect(viewModel.unorganizedCount == 3)
    }

    @Test func profileLoadsRealLibraryStatisticsAndMockStorage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(
            store: store,
            filename: "profile-statistics-library.json"
        )
        let userRepository = MockUserRepository(
            store: store,
            filename: "profile-statistics-users.json",
            delay: .zero
        )
        let user = AuthenticatedUser(
            id: UUID(),
            displayName: "David Caro",
            email: "d.caro@uniandes.edu.co"
        )
        let viewModel = ProfileViewModel(
            authenticatedUser: user,
            userRepository: userRepository,
            videoRepository: libraryRepository,
            folderRepository: libraryRepository,
            exportService: JSONLibraryExportService(
                videoRepository: libraryRepository,
                folderRepository: libraryRepository,
                userRepository: userRepository
            ),
            authenticationRepository: MockAuthenticationRepository(delay: .zero)
        )

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.profile?.displayName == "David Caro")
        #expect(viewModel.statistics.savedCount == 6)
        #expect(viewModel.statistics.folderCount == 4)
        #expect(viewModel.statistics.unorganizedCount == 1)
        #expect(viewModel.statistics.count(for: .tiktok) == 2)
        #expect(viewModel.statistics.count(for: .instagramReel) == 2)
        #expect(viewModel.statistics.count(for: .youtubeShort) == 2)
        #expect(viewModel.storageUsage.percentage == 48)
    }

    @Test func profileAndNotificationChangesPersistBehindUserRepository() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let userRepository = MockUserRepository(
            store: store,
            filename: "profile-persistence-users.json",
            delay: .zero
        )
        let libraryRepository = MockLibraryRepository(
            store: store,
            filename: "profile-persistence-library.json"
        )
        let originalUser = AuthenticatedUser(
            id: UUID(),
            displayName: "Centralia User",
            email: "demo@centralia.app"
        )
        let viewModel = ProfileViewModel(
            authenticatedUser: originalUser,
            userRepository: userRepository,
            videoRepository: libraryRepository,
            folderRepository: libraryRepository,
            exportService: JSONLibraryExportService(
                videoRepository: libraryRepository,
                folderRepository: libraryRepository,
                userRepository: userRepository
            ),
            authenticationRepository: MockAuthenticationRepository(delay: .zero)
        )
        await viewModel.load()

        let updatedUser = await viewModel.updateProfile(
            displayName: "David Caro",
            email: "DAVID@EXAMPLE.COM"
        )
        #expect(updatedUser?.displayName == "David Caro")
        #expect(updatedUser?.email == "david@example.com")

        var preferences = viewModel.notificationPreferences
        preferences.productUpdates = true
        preferences.weeklyLibrarySummary = false
        await viewModel.updateNotificationPreferences(preferences)

        let reloadedRepository = MockUserRepository(
            store: store,
            filename: "profile-persistence-users.json",
            delay: .zero
        )
        let persistedProfile = try await reloadedRepository.profile(for: originalUser)
        let persistedPreferences = try await reloadedRepository.notificationPreferences(
            for: originalUser.id
        )
        #expect(persistedProfile.displayName == "David Caro")
        #expect(persistedProfile.email == "david@example.com")
        #expect(persistedPreferences.productUpdates)
        #expect(persistedPreferences.weeklyLibrarySummary == false)
    }

    @Test func profilePasswordChangeSurfacesCredentialFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let userRepository = MockUserRepository(
            store: store,
            filename: "profile-password-users.json",
            delay: .zero
        )
        let libraryRepository = MockLibraryRepository(
            store: store,
            filename: "profile-password-library.json"
        )
        let user = AuthenticatedUser(
            id: UUID(),
            displayName: "David Caro",
            email: "david@example.com"
        )
        let viewModel = ProfileViewModel(
            authenticatedUser: user,
            userRepository: userRepository,
            videoRepository: libraryRepository,
            folderRepository: libraryRepository,
            exportService: JSONLibraryExportService(
                videoRepository: libraryRepository,
                folderRepository: libraryRepository,
                userRepository: userRepository
            ),
            authenticationRepository: MockAuthenticationRepository(delay: .zero)
        )
        await viewModel.load()

        #expect(
            await viewModel.changePassword(
                currentPassword: "wrong-password",
                newPassword: "new-password"
            ) == false
        )
        #expect(
            viewModel.failureMessage
                == UserRepositoryError.incorrectCurrentPassword.localizedDescription
        )

        #expect(
            await viewModel.changePassword(
                currentPassword: "current-password",
                newPassword: "new-password"
            )
        )
    }

    @Test func libraryExportProducesShareableJSONWithRepositoryData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(
            store: store,
            filename: "profile-export-library.json"
        )
        let userRepository = MockUserRepository(
            store: store,
            filename: "profile-export-users.json",
            delay: .zero
        )
        let authenticatedUser = AuthenticatedUser(
            id: UUID(),
            displayName: "David Caro",
            email: "david@example.com"
        )
        let profile = try await userRepository.profile(for: authenticatedUser)
        let service = JSONLibraryExportService(
            videoRepository: libraryRepository,
            folderRepository: libraryRepository,
            userRepository: userRepository
        )

        let url = try await service.exportLibrary(for: profile)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect((json["videos"] as? [[String: Any]])?.count == 6)
        #expect((json["folders"] as? [[String: Any]])?.count == 4)
        #expect((json["profile"] as? [String: Any])?["displayName"] as? String == "David Caro")
        #expect(json["notificationPreferences"] != nil)
    }
}
