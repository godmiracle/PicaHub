import Foundation

typealias ProductionAccountRepository = DefaultAccountRepository<
    KeychainTokenStore<SystemKeychain>,
    APIAccountAuthenticator
>

struct AppDependencies {
    let accountRepository: ProductionAccountRepository

    init(environment: APIEnvironment = .proxy) {
        let loginClient = APIClient(environment: environment)
        accountRepository = DefaultAccountRepository(
            tokenStore: KeychainTokenStore(),
            authenticator: APIAccountAuthenticator(client: loginClient)
        )
    }
}
