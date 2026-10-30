import Foundation
final class DependencyContainer {
    let authenticationRepository: any AuthenticationRepository
    let videoItemRepository: any VideoItemRepository
    let videoPlaybackRepository: any VideoPlaybackRepository
    let analyticsRepository: any AnalyticsRepository
    let folderRepository: any FolderRepository
    let searchHistoryRepository: any SearchHistoryRepository
    let userRepository: any UserRepository
    let libraryExportService: any LibraryExportService
    let videoImportPipeline: any VideoImportPipeline
    let session: AppSession
    /// Sprint 3: online/offline and changes waiting to sync, for the banner.
    let offlineStatus: OfflineStatus
    /// Kept alive for the whole app (watches the network, sends the outbox).
    private var backgroundServices: [AnyObject] = []

    init(
        authenticationRepository: any AuthenticationRepository,
        videoItemRepository: any VideoItemRepository,
        videoPlaybackRepository: any VideoPlaybackRepository,
        analyticsRepository: any AnalyticsRepository,
        folderRepository: any FolderRepository,
        searchHistoryRepository: any SearchHistoryRepository,
        userRepository: any UserRepository,
        libraryExportService: any LibraryExportService,
        videoImportPipeline: any VideoImportPipeline,
        session: AppSession = AppSession(),
        offlineStatus: OfflineStatus = OfflineStatus()
    ) {
        self.authenticationRepository = authenticationRepository
        self.videoItemRepository = videoItemRepository
        self.videoPlaybackRepository = videoPlaybackRepository
        self.analyticsRepository = analyticsRepository
        self.folderRepository = folderRepository
        self.searchHistoryRepository = searchHistoryRepository
        self.userRepository = userRepository
        self.libraryExportService = libraryExportService
        self.videoImportPipeline = videoImportPipeline
        self.session = session
        self.offlineStatus = offlineStatus
    }

    static func mock() -> DependencyContainer {
        let store = MockDataStore()
        let libraryRepository = MockLibraryRepository(store: store)
        let userRepository = MockUserRepository(store: store)
        return DependencyContainer(
            authenticationRepository: MockAuthenticationRepository(),
            videoItemRepository: libraryRepository,
            videoPlaybackRepository: MockVideoPlaybackRepository(videoRepository: libraryRepository),
            analyticsRepository: MockAnalyticsRepository(),
            folderRepository: libraryRepository,
            searchHistoryRepository: MockSearchHistoryRepository(store: store),
            userRepository: userRepository,
            libraryExportService: JSONLibraryExportService(
                videoRepository: libraryRepository,
                folderRepository: libraryRepository,
                userRepository: userRepository
            ),
            videoImportPipeline: MockVideoImportPipeline()
        )
    }

    static func live() -> DependencyContainer {
        let api = APIClient()
        let client = APILibraryClient(api: api)
        let videosAPI = APIVideoItemRepository(client: client)

        // Sprint 3: offline-first data layer (eventual connectivity, local
        // storage, caching and background work). Mirrors the Android app.
        let status = OfflineStatus()
        let connectivity = ConnectivityMonitor()
        let store = LocalLibraryStore()
        let outbox = PendingActionQueue { count in
            Task { @MainActor in status.pendingChanges = count }
        }
        let memoryCache = LibraryMemoryCache()
        let libraryRepository = OfflineFirstLibraryRepository(
            videosAPI: videosAPI,
            foldersAPI: APIFolderRepository(client: client),
            playbackAPI: APIVideoPlaybackRepository(client: client),
            store: store,
            queue: outbox,
            memory: memoryCache,
            isOnline: { connectivity.isOnline },
            networkType: { NetworkContextMonitor.shared.current }
        )
        let syncManager = SyncManager(queue: outbox) { action in
            try await videosAPI.replay(action)
        } onSynced: {
            status.syncRevision += 1
        }
        let userRepository = OfflineUserRepository(
            remote: APIUserRepository(client: api),
            defaults: UserDefaults(suiteName: "centralia.offline.profile") ?? .standard
        )
        let searchHistoryRepository = OfflineSearchHistoryRepository(
            remote: APISearchHistoryRepository(client: api),
            defaults: UserDefaults(suiteName: "centralia.offline.search") ?? .standard
        )

        // Every time the phone comes back online, send what was queued.
        connectivity.onChange = { online in
            status.isOnline = online
            if online { syncManager.requestSync() }
        }
        Task {
            await outbox.refreshCount()
            syncManager.requestSync()
        }

        let session = AppSession(isRestoringSession: true)
        // Signing out removes this user's offline copy from the phone.
        session.onSignOut = {
            memoryCache.clear()
            userRepository.clear()
            searchHistoryRepository.clear()
            CoverImageLoader.shared.clear()
            Task {
                await store.clear()
                await outbox.clear()
            }
        }

        let container = DependencyContainer(
            authenticationRepository: APIAuthenticationRepository(client: api),
            videoItemRepository: libraryRepository,
            videoPlaybackRepository: libraryRepository,
            analyticsRepository: APIAnalyticsRepository(client: api),
            folderRepository: libraryRepository,
            searchHistoryRepository: searchHistoryRepository,
            userRepository: userRepository,
            libraryExportService: JSONLibraryExportService(
                videoRepository: libraryRepository,
                folderRepository: libraryRepository,
                userRepository: userRepository
            ),
            videoImportPipeline: APIVideoImportPipeline(client: client),
            session: session,
            offlineStatus: status
        )
        container.backgroundServices = [connectivity]
        return container
    }
}
