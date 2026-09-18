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

    @Test func saveWithoutOrganizingPersistsOnlyMetadataAndNote() async throws {
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
        #expect(persistedVideo.tags.isEmpty)
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
        let folder = try await repository.createFolder(named: "Motion")

        let reloadedRepository = MockLibraryRepository(store: store, filename: filename)
        #expect(try await reloadedRepository.folders().contains(folder))

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
}
