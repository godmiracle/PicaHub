import Foundation

protocol AccountAuthenticating: Sendable {
    func login(email: String, password: String) async throws -> String
}

protocol AccountRepository: Sendable {
    func sessionState() async -> AccountSessionState
    func sessionStateUpdates() async -> AsyncStream<AccountSessionState>
    func authenticationToken() async -> String?
    @discardableResult func restoreSession() async -> AccountSessionState
    @discardableResult func authenticate(email: String, password: String) async -> AccountSessionState
    @discardableResult func logout() async -> AccountSessionState
    @discardableResult func invalidateSession() async -> AccountSessionState
}

extension AccountRepository {
    func sessionStateUpdates() async -> AsyncStream<AccountSessionState> {
        let currentState = await sessionState()
        return AsyncStream { continuation in
            continuation.yield(currentState)
            continuation.finish()
        }
    }
}

actor DefaultAccountRepository<Store: TokenStore, Authenticator: AccountAuthenticating>: AccountRepository {
    private let tokenStore: Store
    private let authenticator: Authenticator
    private let cancelAuthenticatedRequests: @Sendable () async -> Void
    private var state: AccountSessionState = .restoring
    private var token: String?
    private var stateContinuations: [UUID: AsyncStream<AccountSessionState>.Continuation] = [:]

    init(
        tokenStore: Store,
        authenticator: Authenticator,
        cancelAuthenticatedRequests: @escaping @Sendable () async -> Void = {}
    ) {
        self.tokenStore = tokenStore
        self.authenticator = authenticator
        self.cancelAuthenticatedRequests = cancelAuthenticatedRequests
    }

    func sessionState() -> AccountSessionState {
        state
    }

    func sessionStateUpdates() async -> AsyncStream<AccountSessionState> {
        let identifier = UUID()
        return AsyncStream { continuation in
            stateContinuations[identifier] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateContinuation(identifier) }
            }
        }
    }

    func authenticationToken() -> String? {
        token
    }

    @discardableResult
    func restoreSession() -> AccountSessionState {
        transition(to: .restoring)
        do {
            token = try tokenStore.loadToken()
            transition(to: token == nil ? .unauthenticated : .authenticated)
        } catch {
            token = nil
            transition(to: .failed(failure(for: error, email: nil)))
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
            transition(to: .failed(
                AccountSessionFailure(
                    kind: .validation,
                    message: "请输入邮箱和密码",
                    email: normalizedEmail.isEmpty ? nil : normalizedEmail,
                    isRetryable: false
                )
            ))
            return state
        }

        transition(to: .authenticating(email: normalizedEmail))
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
            transition(to: .authenticated)
        } catch {
            token = nil
            transition(to: .failed(failure(for: error, email: normalizedEmail)))
        }
        return state
    }

    @discardableResult
    func logout() async -> AccountSessionState {
        await clearSession()
    }

    @discardableResult
    func invalidateSession() async -> AccountSessionState {
        guard token != nil || state != .unauthenticated else {
            return state
        }
        return await clearSession()
    }

    private func clearSession() async -> AccountSessionState {
        token = nil
        transition(to: .unauthenticated)
        await cancelAuthenticatedRequests()
        do {
            try tokenStore.deleteToken()
        } catch {
            transition(to: .failed(failure(for: error, email: nil)))
        }
        return state
    }

    private func transition(to newState: AccountSessionState) {
        state = newState
        stateContinuations.values.forEach { $0.yield(newState) }
    }

    private func removeStateContinuation(_ identifier: UUID) {
        stateContinuations[identifier] = nil
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
