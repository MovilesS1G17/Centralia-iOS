final class DependencyContainer {
    let authenticationRepository: any AuthenticationRepository
    let session: AppSession

    init(
        authenticationRepository: any AuthenticationRepository,
        session: AppSession = AppSession()
    ) {
        self.authenticationRepository = authenticationRepository
        self.session = session
    }

    static func mock() -> DependencyContainer {
        DependencyContainer(authenticationRepository: MockAuthenticationRepository())
    }
}
