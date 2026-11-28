import Foundation
import Observation

@Observable
final class DependencyContainer {
    let authenticationRepository: any AuthenticationRepository
    let videoItemRepository: any VideoItemRepository
    let videoPlaybackRepository: any VideoPlaybackRepository
    let analyticsRepository: any AnalyticsRepository
    let folderRepository: any FolderRepository
    let searchHistoryRepository: any SearchHistoryRepository
    let savedSearchStore: SavedSearchStore
    let recentlyViewed: RecentlyViewedHistory
    let rememberedEmail: any RememberedEmailStoring
    private(set) var sprint4: Sprint4Services?
    let folderSuggestionCache: FolderSuggestionCache
    let userRepository: any UserRepository
    let libraryExportService: any LibraryExportService
    let videoImportPipeline: any VideoImportPipeline
    let session: AppSession
    /// Sprint 3: online/offline and changes waiting to sync, for the banner.
    let offlineStatus: OfflineStatus
    /// Kept alive for the whole app (watches the network, sends the outbox).
    @ObservationIgnored private var backgroundServices: [AnyObject] = []
    @ObservationIgnored private var sprint4Activation: Task<Void, Never>?
    @ObservationIgnored private var sprint4Cleanup: Task<Void, Never>?

    init(
        authenticationRepository: any AuthenticationRepository,
        videoItemRepository: any VideoItemRepository,
        videoPlaybackRepository: any VideoPlaybackRepository,
        analyticsRepository: any AnalyticsRepository,
        folderRepository: any FolderRepository,
        searchHistoryRepository: any SearchHistoryRepository,
        savedSearchStore: SavedSearchStore = SavedSearchStore(),
        recentlyViewed: RecentlyViewedHistory,
        rememberedEmail: any RememberedEmailStoring = InMemoryRememberedEmailStore(),
        makeSprint4Services: @escaping (UUID) -> Sprint4Services,
        folderSuggestionCache: FolderSuggestionCache = FolderSuggestionCache(),
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
        self.savedSearchStore = savedSearchStore
        self.recentlyViewed = recentlyViewed
        self.rememberedEmail = rememberedEmail
        self.folderSuggestionCache = folderSuggestionCache
        self.userRepository = userRepository
        self.libraryExportService = libraryExportService
        self.videoImportPipeline = videoImportPipeline
        self.session = session
        self.offlineStatus = offlineStatus

        let didAuthenticate = session.onAuthenticated
        session.onAuthenticated = { [weak self] accountID in
            didAuthenticate?(accountID)
            self?.activateSprint4(for: accountID, makeServices: makeSprint4Services)
        }
        let didSignOut = session.onSignOut
        session.onSignOut = { [weak self] in
            self?.endSprint4Session()
            didSignOut?()
        }
    }

    private func activateSprint4(for accountID: UUID, makeServices: @escaping (UUID) -> Sprint4Services) {
        endSprint4Session()
        let cleanup = sprint4Cleanup
        sprint4Activation = Task { [weak self] in
            await cleanup?.value
            guard let self, !Task.isCancelled, session.authenticatedUserID == accountID else { return }
            sprint4Cleanup = nil
            sprint4 = makeServices(accountID)
        }
    }

    private func endSprint4Session() {
        sprint4Activation?.cancel()
        sprint4Activation = nil
        if let sprint4 { sprint4Cleanup = sprint4.endSession() }
        sprint4 = nil
    }

    static func mock(
        store: MockDataStore = MockDataStore(),
        savedSearchStore: SavedSearchStore = SavedSearchStore(),
        folderSuggestionCache: FolderSuggestionCache = FolderSuggestionCache(),
        includeSampleContent: Bool = true,
        offlineDemoDirectory: URL? = nil,
        offline: Bool = false
    ) -> DependencyContainer {
        let libraryRepository = MockLibraryRepository(store: store, includeSampleContent: includeSampleContent)
        let userRepository = MockUserRepository(store: store)
        let session = AppSession()
        let recentlyViewed = RecentlyViewedHistory(store: InMemoryRecentlyViewedStore())
        let clearSessionData = { [weak session] in
            recentlyViewed.clear()
            if let accountID = session?.authenticatedUserID {
                Task { await folderSuggestionCache.clear(for: accountID) }
            }
        }
        let status = OfflineStatus()
        status.isOnline = !offline
        let playback = MockVideoPlaybackRepository(videoRepository: libraryRepository)
        let offlineLibrary = offlineDemoDirectory.map { directory in
            makeOfflineLibrary(
                videos: libraryRepository,
                folders: libraryRepository,
                playback: playback,
                directory: directory,
                status: status,
                session: session,
                replayVideo: { _ in },
                onSignOut: clearSessionData
            )
        }
        if offlineLibrary == nil { session.onSignOut = clearSessionData }
        let folders: any FolderRepository = offlineLibrary.map { $0 as any FolderRepository } ?? libraryRepository
        return DependencyContainer(
            authenticationRepository: MockAuthenticationRepository(),
            videoItemRepository: libraryRepository,
            videoPlaybackRepository: playback,
            analyticsRepository: MockAnalyticsRepository(),
            folderRepository: folders,
            searchHistoryRepository: MockSearchHistoryRepository(store: store),
            savedSearchStore: savedSearchStore,
            recentlyViewed: recentlyViewed,
            makeSprint4Services: { _ in
                Sprint4Services(
                    dismissals: InMemoryRediscoverDismissals(),
                    watchLater: InMemoryWatchLaterStore(),
                    trends: CachedTrendsRepository(
                        fetch: { days in
                            if offline { throw TrendsUnavailableError() }
                            return APITrendsClient.sample(windowDays: days)
                        },
                        disk: InMemoryTrendsDiskStore()
                    ),
                    insights: InMemoryInsightsSnapshotStore()
                )
            },
            folderSuggestionCache: folderSuggestionCache,
            userRepository: userRepository,
            libraryExportService: JSONLibraryExportService(
                videoRepository: libraryRepository,
                folderRepository: folders,
                userRepository: userRepository
            ),
            videoImportPipeline: MockVideoImportPipeline(),
            session: session,
            offlineStatus: status
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
        let session = AppSession(isRestoringSession: true)
        let recentlyViewed = RecentlyViewedHistory(store: CoreDataRecentlyViewedStore())
        let trendsClient = APITrendsClient(client: api)
        let folderSuggestionCache = FolderSuggestionCache()
        let userRepository = OfflineUserRepository(
            remote: APIUserRepository(client: api),
            defaults: UserDefaults(suiteName: "centralia.offline.profile") ?? .standard
        )
        let searchHistoryRepository = OfflineSearchHistoryRepository(
            remote: APISearchHistoryRepository(client: api),
            defaults: UserDefaults(suiteName: "centralia.offline.search") ?? .standard
        )

        let libraryRepository = makeOfflineLibrary(
            videos: videosAPI,
            folders: APIFolderRepository(client: client),
            playback: APIVideoPlaybackRepository(client: client),
            directory: LocalLibraryStore.defaultDirectory,
            status: status,
            session: session,
            replayVideo: { try await videosAPI.replay($0) },
            onSignOut: { [weak session] in
                recentlyViewed.clear()
                userRepository.clear()
                searchHistoryRepository.clear()
                CoverImageLoader.shared.clear()
                if let accountID = session?.authenticatedUserID {
                    Task { await folderSuggestionCache.clear(for: accountID) }
                }
            }
        )

        let container = DependencyContainer(
            authenticationRepository: APIAuthenticationRepository(client: api),
            videoItemRepository: libraryRepository,
            videoPlaybackRepository: libraryRepository,
            analyticsRepository: APIAnalyticsRepository(client: api),
            folderRepository: libraryRepository,
            searchHistoryRepository: searchHistoryRepository,
            recentlyViewed: recentlyViewed,
            rememberedEmail: KeychainRememberedEmailStore(),
            makeSprint4Services: { accountID in
                let token = try? api.tokenStore.accessToken()
                let tracker = token.map {
                    BatchingAnalyticsTracker(repository: APIAnalyticsRepository(
                        client: api, sessionToken: $0, isOnline: { [weak status] in status?.isOnline == true }
                    ))
                }
                return Sprint4Services(
                    dismissals: UserDefaultsRediscoverDismissals(accountID: accountID),
                    watchLater: CoreDataWatchLaterStore(accountID: accountID),
                    trends: CachedTrendsRepository(
                        fetch: { days in try await trendsClient.trends(windowDays: days) },
                        disk: FileTrendsDiskStore()
                    ),
                    insights: FileInsightsSnapshotStore(accountID: accountID),
                    tracker: tracker
                )
            },
            folderSuggestionCache: folderSuggestionCache,
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
        connectivity.onChange = { [weak container] online in
            status.isOnline = online
            status.retrySync()
            if online { Task { await container?.sprint4?.flushAnalytics() } }
        }
        container.backgroundServices = [connectivity]
        return container
    }

    private static func makeOfflineLibrary(
        videos: any VideoItemRepository,
        folders: any FolderRepository,
        playback: any VideoPlaybackRepository,
        directory: URL,
        status: OfflineStatus,
        session: AppSession,
        replayVideo: @escaping @Sendable (PendingAction) async throws -> Void,
        onSignOut: @escaping () -> Void = {}
    ) -> OfflineFirstLibraryRepository {
        let store = LocalLibraryStore(directory: directory)
        let outbox = PendingActionQueue(directory: directory) { [weak status] actions, revision in
            Task { @MainActor in status?.updateOutbox(actions, revision: revision) }
        }
        let memory = LibraryMemoryCache()
        let library = OfflineFirstLibraryRepository(
            videosAPI: videos,
            foldersAPI: folders,
            playbackAPI: playback,
            store: store,
            queue: outbox,
            memory: memory,
            isOnline: { [weak status] in status?.isOnline == true },
            networkType: { NetworkContextMonitor.shared.current },
            currentAccountID: { [weak session] in session?.authenticatedUserID },
            onFolderChange: { [weak status] folders, account in status?.updateFolders(folders, for: account) },
            onRenameQueued: { [weak status] rename in
                status?.clearRenameNotice(for: rename.folderID)
                status?.retrySync()
            }
        )
        let sync = SyncManager(
            queue: outbox,
            canSend: { [weak status, weak session] action in
                guard status?.isOnline == true, let account = session?.authenticatedUserID else { return false }
                return (action.folderRename?.userID ?? account) == account
            },
            send: { action in
                if let rename = action.folderRename {
                    try await library.replayFolderRename(rename, queuedAt: action.queuedAt)
                } else {
                    try await replayVideo(action)
                }
            },
            onRenameSettled: { [weak status, weak session] rename, notice in
                await library.publishFolders(for: rename.userID)
                let stillPending = await outbox.all().contains {
                    $0.folderRename?.userID == rename.userID && $0.folderRename?.folderID == rename.folderID
                }
                if !stillPending {
                    status?.reportRename(rename, notice: notice)
                    if notice == .folderRemoved, session?.authenticatedUserID == rename.userID {
                        status?.syncRevision += 1
                    }
                }
            },
            onSynced: { [weak status] in status?.syncRevision += 1 }
        )
        status.requestSync = { sync.requestSync() }
        session.onAuthenticated = { [weak status] account in
            status?.activate(accountID: account)
            Task { @MainActor in
                await outbox.publishState()
                status?.retrySync()
            }
        }
        session.onSignOut = { [weak status] in
            status?.activate(accountID: nil)
            memory.clear()
            onSignOut()
            Task {
                await store.clear()
                await outbox.clear()
            }
        }
        return library
    }
}
