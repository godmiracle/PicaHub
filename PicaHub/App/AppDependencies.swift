import Foundation

typealias ProductionAccountRepository = DefaultAccountRepository<
    KeychainTokenStore<SystemKeychain>,
    APIAccountAuthenticator
>

struct AppDependencies {
    let accountRepository: any AccountRepository
    let apiClient: APIClient

    init(environment: APIEnvironment = .proxy) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let isAuthenticated = ProcessInfo.processInfo.arguments.contains("--uitest-authenticated")
            accountRepository = UITestAccountRepository(
                initialState: isAuthenticated ? .authenticated : .unauthenticated
            )
            apiClient = APIClient(environment: environment)
            return
        }
#endif
        let loginClient = APIClient(environment: environment)
        let authenticatedRequests = AuthenticatedRequestController()
        let repository = DefaultAccountRepository(
            tokenStore: KeychainTokenStore(),
            authenticator: APIAccountAuthenticator(client: loginClient),
            cancelAuthenticatedRequests: { await authenticatedRequests.cancelAll() }
        )
        accountRepository = repository
        apiClient = APIClient(
            environment: environment,
            tokenProvider: { await repository.authenticationToken() },
            sessionExpiredHandler: { await repository.invalidateSession() },
            authenticatedRequests: authenticatedRequests
        )
    }
}
