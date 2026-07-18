import Foundation

protocol AccountAuthenticating: Sendable {
    func login(email: String, password: String) async throws -> String
}

protocol AccountRepository: Sendable {
    func sessionState() async -> AccountSessionState
    func authenticationToken() async -> String?
    @discardableResult func restoreSession() async -> AccountSessionState
    @discardableResult func authenticate(email: String, password: String) async -> AccountSessionState
}

actor DefaultAccountRepository<Store: TokenStore, Authenticator: AccountAuthenticating>: AccountRepository {
    private let tokenStore: Store
    private let authenticator: Authenticator
    private var state: AccountSessionState = .restoring
    private var token: String?

    init(tokenStore: Store, authenticator: Authenticator) {
        self.tokenStore = tokenStore
        self.authenticator = authenticator
    }

    func sessionState() -> AccountSessionState {
        state
    }

    func authenticationToken() -> String? {
        token
    }

    @discardableResult
    func restoreSession() -> AccountSessionState {
        state = .restoring
        do {
            token = try tokenStore.loadToken()
            state = token == nil ? .unauthenticated : .authenticated
        } catch {
            token = nil
            state = .failed(failure(for: error, email: nil))
        }
        return state
    }

    @discardableResult
    func authenticate(email: String, password: String) async -> AccountSessionState {
        if case .authenticating = state {
            return state
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            state = .failed(
                AccountSessionFailure(
                    kind: .validation,
                    message: "请输入邮箱和密码",
                    email: normalizedEmail.isEmpty ? nil : normalizedEmail,
                    isRetryable: false
                )
            )
            return state
        }

        state = .authenticating(email: normalizedEmail)
        do {
            let receivedToken = try await authenticator.login(
                email: normalizedEmail,
                password: password
            )
            guard !receivedToken.isEmpty else {
                throw TokenStoreError.invalidToken
            }
            try tokenStore.saveToken(receivedToken)
            token = receivedToken
            state = .authenticated
        } catch {
            token = nil
            state = .failed(failure(for: error, email: normalizedEmail))
        }
        return state
    }

    private func failure(for error: Error, email: String?) -> AccountSessionFailure {
        if error is TokenStoreError {
            return AccountSessionFailure(
                kind: .secureStorage,
                message: "无法安全保存登录状态，请稍后重试",
                email: email,
                isRetryable: true
            )
        }

        guard let apiError = error as? APIError else {
            return AccountSessionFailure(
                kind: .unknown,
                message: "登录失败，请稍后重试",
                email: email,
                isRetryable: true
            )
        }

        switch apiError {
        case .connection, .timedOut:
            return AccountSessionFailure(
                kind: .network,
                message: apiError.userMessage,
                email: email,
                isRetryable: true
            )
        case .service, .authenticationRequired, .sessionExpired:
            return AccountSessionFailure(
                kind: .authentication,
                message: apiError.userMessage,
                email: email,
                isRetryable: false
            )
        default:
            return AccountSessionFailure(
                kind: .unknown,
                message: apiError.userMessage,
                email: email,
                isRetryable: true
            )
        }
    }
}
