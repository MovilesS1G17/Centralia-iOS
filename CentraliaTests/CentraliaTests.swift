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
}
