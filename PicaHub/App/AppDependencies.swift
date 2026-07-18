import Foundation

typealias ProductionAccountRepository = DefaultAccountRepository<
    KeychainTokenStore<SystemKeychain>,
    APIAccountAuthenticator
>

struct AppDependencies {
    let accountRepository: ProductionAccountRepository
    let apiClient: APIClient

    init(environment: APIEnvironment = .proxy) {
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
