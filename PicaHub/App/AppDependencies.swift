import Foundation

typealias ProductionAccountRepository = DefaultAccountRepository<
    KeychainTokenStore<SystemKeychain>,
    APIAccountAuthenticator
>

@MainActor
struct AppDependencies {
    let accountRepository: any AccountRepository
    let categoryRepository: any CategoryRepository
    let comicRepository: any ComicRepository
    let comicDetailsRepository: any ComicDetailsRepository
    let favoriteRepository: any FavoriteRepository
    let categoryImageCache: CategoryImageCache
    let apiClient: APIClient
    let imageURLBuilder: ImageURLBuilder
    let readerDependencies: ReaderDependencies

    init(environment: APIEnvironment = .proxy) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let isAuthenticated = ProcessInfo.processInfo.arguments.contains("--uitest-authenticated")
            accountRepository = UITestAccountRepository(
                initialState: isAuthenticated ? .authenticated : .unauthenticated
            )
            categoryRepository = UITestCategoryRepository()
            comicRepository = UITestComicRepository()
            comicDetailsRepository = UITestComicDetailsRepository()
            favoriteRepository = UITestFavoriteRepository()
            categoryImageCache = CategoryImageCache()
            apiClient = APIClient(environment: environment)
            imageURLBuilder = ImageURLBuilder(environment: environment)
            readerDependencies = ReaderDependencies(
                chapterImageRepository: UITestChapterImageRepository(),
                imagePipeline: ImagePipeline(),
                progressStore: UserDefaultsReadingProgressStore()
            )
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
        comicRepository = APIComicRepository(client: client)
        comicDetailsRepository = APIComicDetailsRepository(client: client)
        favoriteRepository = APIFavoriteRepository(client: client)
        categoryImageCache = CategoryImageCache()
        imageURLBuilder = ImageURLBuilder(environment: environment)
        readerDependencies = ReaderDependencies(
            chapterImageRepository: APIChapterImageRepository(client: client),
            imagePipeline: ImagePipeline(),
            progressStore: UserDefaultsReadingProgressStore()
        )
    }
}
