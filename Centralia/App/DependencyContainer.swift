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
    /// "Recently viewed" history (Core Data on the phone).
    let recentlyViewed: any RecentlyViewedStoring
    /// "Remember my email" on the sign-in screen (Keychain).
    let rememberedEmail: any RememberedEmailStoring
    /// Sprint 4: what the five new views need (Core Data queue, Trends cache, …).
    let sprint4: Sprint4Services
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
        offlineStatus: OfflineStatus = OfflineStatus(),
        recentlyViewed: any RecentlyViewedStoring = InMemoryRecentlyViewedStore(),
        rememberedEmail: any RememberedEmailStoring = InMemoryRememberedEmailStore(),
        sprint4: Sprint4Services = .inMemory()
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
        self.recentlyViewed = recentlyViewed
        self.rememberedEmail = rememberedEmail
        self.sprint4 = sprint4
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
        // Local storage, relational (David): Core Data for "Recently viewed".
        let recentlyViewed = CoreDataRecentlyViewedStore()
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

        // ---- Sprint 4
        // Feature events for BQ11-15: buffered, sent in batches, retried later
        // when offline (eventual connectivity).
        let analytics = BatchingAnalyticsTracker(repository: APIAnalyticsRepository(client: api))
        let sprint4 = Sprint4Services(
            analytics: analytics,
            // Key/value (UserDefaults): Rediscover's "Not now".
            dismissals: UserDefaultsRediscoverDismissals(),
            // Local storage, relational (Core Data): the Watch later queue.
            watchLater: CoreDataWatchLaterStore(),
            // Caching: LRU in memory + JSON in Caches in front of GET /v1/trends.
            trends: CachedTrendsRepository(
                fetch: { days in try await APITrendsClient(client: api).trends(windowDays: days) },
                disk: FileTrendsDiskStore()
            ),
            creatorsCache: CreatorsCache(),
            // Files: the last Insights snapshot.
            insights: FileInsightsSnapshotStore()
        )

        // Every time the phone comes back online, send what was queued.
        connectivity.onChange = { online in
            status.isOnline = online
            if online {
                syncManager.requestSync()
                Task { await analytics.flush() }
            }
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
                await recentlyViewed.clear()
                await sprint4.clear()
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
            offlineStatus: status,
            recentlyViewed: recentlyViewed,
            // Local storage, Keychain (Gustavo): the remembered sign-in email.
            rememberedEmail: KeychainRememberedEmailStore(),
            sprint4: sprint4
        )
        container.backgroundServices = [connectivity]
        return container
    }
}
