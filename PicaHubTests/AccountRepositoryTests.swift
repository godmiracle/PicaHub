import Foundation
import Testing
@testable import PicaHub

private final class TokenStoreStub: TokenStore, @unchecked Sendable {
    var storedToken: String?
    var loadError: TokenStoreError?
    var saveError: TokenStoreError?
    private(set) var savedTokens: [String] = []

    func loadToken() throws -> String? {
        if let loadError { throw loadError }
        return storedToken
    }

    func saveToken(_ token: String) throws {
        if let saveError { throw saveError }
        savedTokens.append(token)
        storedToken = token
    }

    func deleteToken() throws {
        storedToken = nil
    }
}

private struct AuthenticationStub: AccountAuthenticating {
    let result: Result<String, APIError>

    func login(email: String, password: String) async throws -> String {
        try result.get()
    }
}

private actor AuthenticationGate: AccountAuthenticating {
    private var continuation: CheckedContinuation<String, Error>?
    private(set) var callCount = 0

    func login(email: String, password: String) async throws -> String {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func succeed(token: String) {
        continuation?.resume(returning: token)
        continuation = nil
    }
}

struct AccountRepositoryTests {
    @Test func startsInRestoringState() async {
        let repository = makeRepository()

        #expect(await repository.sessionState() == .restoring)
    }

    @Test func restoreWithoutTokenBecomesUnauthenticated() async {
        let repository = makeRepository()

        #expect(await repository.restoreSession() == .unauthenticated)
        #expect(await repository.authenticationToken() == nil)
    }

    @Test func restoreWithTokenBecomesAuthenticated() async {
        let store = TokenStoreStub()
        store.storedToken = "stored-token"
        let repository = makeRepository(store: store)

        #expect(await repository.restoreSession() == .authenticated)
        #expect(await repository.authenticationToken() == "stored-token")
    }

    @Test func successfulLoginPersistsToken() async {
        let store = TokenStoreStub()
        let repository = makeRepository(
            store: store,
            result: .success("session-token")
        )

        let state = await repository.authenticate(
            email: "  user@example.com ",
            password: "password"
        )

        #expect(state == .authenticated)
        #expect(store.savedTokens == ["session-token"])
        #expect(await repository.authenticationToken() == "session-token")
    }

    @Test func rejectedLoginKeepsOnlyEmailInFailure() async {
        let repository = makeRepository(
            result: .failure(.service(statusCode: 400, message: "账号或密码错误"))
        )

        let state = await repository.authenticate(
            email: "user@example.com",
            password: "secret-password"
        )

        #expect(
            state == .failed(
                AccountSessionFailure(
                    kind: .authentication,
                    message: "账号或密码错误",
                    email: "user@example.com",
                    isRetryable: false
                )
            )
        )
        #expect(String(describing: state).contains("secret-password") == false)
    }

    @Test func keychainFailureDoesNotKeepTokenInMemory() async {
        let store = TokenStoreStub()
        store.saveError = .unavailable(status: -1)
        let repository = makeRepository(store: store, result: .success("session-token"))

        let state = await repository.authenticate(email: "user@example.com", password: "password")

        guard case let .failed(failure) = state else {
            Issue.record("Expected a failed state")
            return
        }
        #expect(failure.kind == .secureStorage)
        #expect(await repository.authenticationToken() == nil)
    }

    @Test func duplicateLoginIsPreventedWhileAuthenticating() async {
        let store = TokenStoreStub()
        let gate = AuthenticationGate()
        let repository = DefaultAccountRepository(tokenStore: store, authenticator: gate)
        let firstLogin = Task {
            await repository.authenticate(email: "user@example.com", password: "password")
        }

        while await repository.sessionState() != .authenticating(email: "user@example.com") {
            await Task.yield()
        }
        let duplicateState = await repository.authenticate(
            email: "other@example.com",
            password: "other-password"
        )
        #expect(duplicateState == .authenticating(email: "user@example.com"))
        #expect(await gate.callCount == 1)

        await gate.succeed(token: "session-token")
        #expect(await firstLogin.value == .authenticated)
    }

    private func makeRepository(
        store: TokenStoreStub = TokenStoreStub(),
        result: Result<String, APIError> = .success("token")
    ) -> DefaultAccountRepository<TokenStoreStub, AuthenticationStub> {
        DefaultAccountRepository(
            tokenStore: store,
            authenticator: AuthenticationStub(result: result)
        )
    }
}
