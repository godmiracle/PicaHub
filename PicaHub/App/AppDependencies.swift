import Foundation

typealias ProductionAccountRepository = DefaultAccountRepository<
    KeychainTokenStore<SystemKeychain>,
    APIAccountAuthenticator
>

@MainActor
struct AppDependencies {
    let accountRepository: any AccountRepository
    let categoryRepository: any CategoryRepository
    let categoryImageCache: CategoryImageCache
    let apiClient: APIClient
    let imageURLBuilder: ImageURLBuilder

    init(environment: APIEnvironment = .proxy) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let isAuthenticated = ProcessInfo.processInfo.arguments.contains("--uitest-authenticated")
            accountRepository = UITestAccountRepository(
                initialState: isAuthenticated ? .authenticated : .unauthenticated
            )
            categoryRepository = UITestCategoryRepository()
            categoryImageCache = CategoryImageCache()
            apiClient = APIClient(environment: environment)
            imageURLBuilder = ImageURLBuilder(environment: environment)
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
        let client = APIClient(
            environment: environment,
            tokenProvider: { await repository.authenticationToken() },
            sessionExpiredHandler: { await repository.invalidateSession() },
            authenticatedRequests: authenticatedRequests
        )
        apiClient = client
        categoryRepository = APICategoryRepository(client: client)
        categoryImageCache = CategoryImageCache()
        imageURLBuilder = ImageURLBuilder(environment: environment)
    }
}
