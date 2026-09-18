final class DependencyContainer {
    let authenticationRepository: any AuthenticationRepository
    let videoItemRepository: any VideoItemRepository
    let folderRepository: any FolderRepository
    let searchHistoryRepository: any SearchHistoryRepository
    let videoImportPipeline: any VideoImportPipeline
    let session: AppSession

    init(
        authenticationRepository: any AuthenticationRepository,
        videoItemRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        searchHistoryRepository: any SearchHistoryRepository,
        videoImportPipeline: any VideoImportPipeline,
        session: AppSession = AppSession()
    ) {
        self.authenticationRepository = authenticationRepository
        self.videoItemRepository = videoItemRepository
        self.folderRepository = folderRepository
        self.searchHistoryRepository = searchHistoryRepository
        self.videoImportPipeline = videoImportPipeline
        self.session = session
    }

    static func mock() -> DependencyContainer {
        let store = MockDataStore()
        let libraryRepository = MockLibraryRepository(store: store)
        return DependencyContainer(
            authenticationRepository: MockAuthenticationRepository(),
            videoItemRepository: libraryRepository,
            folderRepository: libraryRepository,
            searchHistoryRepository: MockSearchHistoryRepository(store: store),
            videoImportPipeline: MockVideoImportPipeline()
        )
    }
}
