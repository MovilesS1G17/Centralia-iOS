final class DependencyContainer {
    let authenticationRepository: any AuthenticationRepository
    let videoItemRepository: any VideoItemRepository
    let folderRepository: any FolderRepository
    let searchRepository: any SearchRepository
    let searchHistoryRepository: any SearchHistoryRepository
    let userRepository: any UserRepository
    let libraryExportService: any LibraryExportService
    let videoImportPipeline: any VideoImportPipeline
    let session: AppSession

    init(
        authenticationRepository: any AuthenticationRepository,
        videoItemRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        searchRepository: any SearchRepository,
        searchHistoryRepository: any SearchHistoryRepository,
        userRepository: any UserRepository,
        libraryExportService: any LibraryExportService,
        videoImportPipeline: any VideoImportPipeline,
        session: AppSession = AppSession()
    ) {
        self.authenticationRepository = authenticationRepository
        self.videoItemRepository = videoItemRepository
        self.folderRepository = folderRepository
        self.searchRepository = searchRepository
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
            folderRepository: libraryRepository,
            searchRepository: MockSearchRepository(videoRepository: libraryRepository),
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
        let store = MockDataStore()
        let userRepository = MockUserRepository(store: store)
        let client = APILibraryClient()
        let videoRepository = APIVideoItemRepository(client: client)
        let folderRepository = APIFolderRepository(client: client)
        return DependencyContainer(
            authenticationRepository: APIAuthenticationRepository(configuration: .current),
            videoItemRepository: videoRepository,
            folderRepository: folderRepository,
            searchRepository: APISearchRepository(client: client),
            searchHistoryRepository: MockSearchHistoryRepository(store: store),
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
