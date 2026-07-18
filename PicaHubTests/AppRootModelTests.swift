import Testing
@testable import PicaHub

private actor RootRepositoryStub: AccountRepository {
    var state: AccountSessionState
    private(set) var restoreCallCount = 0

    init(state: AccountSessionState) {
        self.state = state
    }

    func sessionState() -> AccountSessionState { state }
    func authenticationToken() -> String? { nil }

    func restoreSession() -> AccountSessionState {
        restoreCallCount += 1
        return state
    }

    func authenticate(email: String, password: String) -> AccountSessionState {
        state
    }
}

@MainActor
struct AppRootModelTests {
    @Test func startsInNonInteractiveRestoringState() {
        let repository = RootRepositoryStub(state: .unauthenticated)
        let model = AppRootModel(repository: repository)

        #expect(model.state == .restoring)
    }

    @Test func noStoredTokenRoutesToLogin() async {
        let repository = RootRepositoryStub(state: .unauthenticated)
        let model = AppRootModel(repository: repository)

        await model.restoreSession()

        #expect(model.state == .unauthenticated)
        #expect(await repository.restoreCallCount == 1)
    }

    @Test func storedTokenRoutesToAuthenticatedContent() async {
        let repository = RootRepositoryStub(state: .authenticated)
        let model = AppRootModel(repository: repository)

        await model.restoreSession()

        #expect(model.state == .authenticated)
    }

    @Test func keychainFailureRemainsVisibleForRetry() async {
        let failure = AccountSessionFailure(
            kind: .secureStorage,
            message: "无法安全保存登录状态，请稍后重试",
            email: nil,
            isRetryable: true
        )
        let repository = RootRepositoryStub(state: .failed(failure))
        let model = AppRootModel(repository: repository)

        await model.restoreSession()

        #expect(model.state == .failed(failure))
    }

    @Test func successfulLoginSynchronizationRoutesToAuthenticatedContent() async {
        let repository = RootRepositoryStub(state: .authenticated)
        let model = AppRootModel(repository: repository)

        await model.synchronizeAfterLogin()

        #expect(model.state == .authenticated)
    }
}
