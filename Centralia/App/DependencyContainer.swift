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
        session: AppSession = AppSession()
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
        let userRepository = APIUserRepository(client: api)
        let videoRepository = APIVideoItemRepository(client: client)
        let folderRepository = APIFolderRepository(client: client)
        return DependencyContainer(
            authenticationRepository: APIAuthenticationRepository(client: api),
            videoItemRepository: videoRepository,
            videoPlaybackRepository: APIVideoPlaybackRepository(client: client),
            analyticsRepository: APIAnalyticsRepository(client: api),
            folderRepository: folderRepository,
            searchHistoryRepository: APISearchHistoryRepository(client: api),
            userRepository: userRepository,
            libraryExportService: JSONLibraryExportService(
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                userRepository: userRepository
            ),
            videoImportPipeline: APIVideoImportPipeline(client: client),
            session: AppSession(isRestoringSession: true)
        )
    }
}
