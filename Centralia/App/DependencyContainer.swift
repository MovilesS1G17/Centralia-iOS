final class DependencyContainer {
    let authenticationRepository: any AuthenticationRepository
    let videoItemRepository: any VideoItemRepository
    let folderRepository: any FolderRepository
    let session: AppSession

    init(
        authenticationRepository: any AuthenticationRepository,
        videoItemRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        session: AppSession = AppSession()
    ) {
        self.authenticationRepository = authenticationRepository
        self.videoItemRepository = videoItemRepository
        self.folderRepository = folderRepository
        self.session = session
    }

    static func mock() -> DependencyContainer {
        let libraryRepository = MockLibraryRepository()
        return DependencyContainer(
            authenticationRepository: MockAuthenticationRepository(),
            videoItemRepository: libraryRepository,
            folderRepository: libraryRepository
        )
    }
}
