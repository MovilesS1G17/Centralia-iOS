import Foundation
import Observation

@Observable
final class ProfileViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let authenticatedUser: AuthenticatedUser
    private let userRepository: any UserRepository
    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let exportService: any LibraryExportService
    private let authenticationRepository: any AuthenticationRepository

    private(set) var state: LoadState = .idle
    private(set) var profile: UserProfile?
    private(set) var statistics = LibraryStatistics.empty
    private(set) var notificationPreferences = NotificationPreferences.defaults
    private(set) var storageUsage = ProfileStorageUsage.mock
    private(set) var isUpdatingProfile = false
    private(set) var isChangingPassword = false
    private(set) var isSavingPreferences = false
    private(set) var isExporting = false
    private(set) var isSigningOut = false
    private(set) var failureMessage: String?

    init(
        authenticatedUser: AuthenticatedUser,
        userRepository: any UserRepository,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        exportService: any LibraryExportService,
        authenticationRepository: any AuthenticationRepository
    ) {
        self.authenticatedUser = authenticatedUser
        self.userRepository = userRepository
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.exportService = exportService
        self.authenticationRepository = authenticationRepository
    }

    func load() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading
        failureMessage = nil

        do {
            let loadedProfile = try await userRepository.profile(for: authenticatedUser)

            async let loadedVideos = videoRepository.videos()
            async let loadedFolders = folderRepository.folders()
            async let loadedPreferences = userRepository.notificationPreferences(
                for: loadedProfile.id
            )
            let (videos, folders, preferences) = try await (
                loadedVideos,
                loadedFolders,
                loadedPreferences
            )

            profile = loadedProfile
            notificationPreferences = preferences
            statistics = Self.statistics(videos: videos, folders: folders)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        state = .idle
        await load()
    }

    func updateProfile(displayName: String, email: String) async -> AuthenticatedUser? {
        guard let profile, !isUpdatingProfile else { return nil }
        isUpdatingProfile = true
        failureMessage = nil
        defer { isUpdatingProfile = false }

        do {
            let updatedProfile = try await userRepository.updateProfile(
                UserProfile(
                    id: profile.id,
                    displayName: displayName,
                    email: email,
                    membershipStatus: profile.membershipStatus
                )
            )
            self.profile = updatedProfile
            return updatedProfile.authenticatedUser
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        guard let profile, !isChangingPassword else { return false }
        isChangingPassword = true
        failureMessage = nil
        defer { isChangingPassword = false }

        do {
            try await userRepository.changePassword(
                for: profile.id,
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            return true
        } catch {
            failureMessage = error.localizedDescription
            return false
        }
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async {
        guard let profile, !isSavingPreferences else { return }
        let previousPreferences = notificationPreferences
        notificationPreferences = preferences
        isSavingPreferences = true
        failureMessage = nil
        defer { isSavingPreferences = false }

        do {
            notificationPreferences = try await userRepository.updateNotificationPreferences(
                preferences,
                for: profile.id
            )
        } catch {
            notificationPreferences = previousPreferences
            failureMessage = error.localizedDescription
        }
    }

    func prepareExport() async -> URL? {
        guard let profile, !isExporting else { return nil }
        isExporting = true
        failureMessage = nil
        defer { isExporting = false }

        do {
            return try await exportService.exportLibrary(for: profile)
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    func signOut() async -> Bool {
        guard !isSigningOut else { return false }
        isSigningOut = true
        failureMessage = nil
        defer { isSigningOut = false }

        do {
            try await authenticationRepository.signOut()
            return true
        } catch {
            failureMessage = error.localizedDescription
            return false
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private static func statistics(
        videos: [VideoItem],
        folders: [LibraryFolder]
    ) -> LibraryStatistics {
        var platformCounts: [VideoPlatform: Int] = [:]
        for video in videos {
            platformCounts[video.platform, default: 0] += 1
        }

        return LibraryStatistics(
            savedCount: videos.count,
            folderCount: folders.count,
            unorganizedCount: videos.count(where: { $0.folderID == nil }),
            platformCounts: platformCounts
        )
    }
}

private extension ProfileViewModel.LoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
