#if DEBUG
import Foundation

actor UITestAccountRepository: AccountRepository {
    private var state: AccountSessionState
    private var continuation: AsyncStream<AccountSessionState>.Continuation?

    init(initialState: AccountSessionState) {
        state = initialState
    }

    func sessionState() -> AccountSessionState { state }

    func sessionStateUpdates() async -> AsyncStream<AccountSessionState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(state)
        }
    }

    func authenticationToken() -> String? {
        state == .authenticated ? "ui-test-token" : nil
    }

    func restoreSession() -> AccountSessionState {
        continuation?.yield(state)
        return state
    }

    func authenticate(email: String, password: String) async -> AccountSessionState {
        transition(to: .authenticating(email: email))
        try? await Task.sleep(for: .milliseconds(150))
        if password == "password" {
            transition(to: .authenticated)
        } else {
            transition(
                to: .failed(
                    AccountSessionFailure(
                        kind: .authentication,
                        message: "账号或密码错误",
                        email: email,
                        isRetryable: false
                    )
                )
            )
        }
        return state
    }

    func logout() -> AccountSessionState {
        transition(to: .unauthenticated)
        return state
    }

    func invalidateSession() -> AccountSessionState {
        transition(to: .unauthenticated)
        return state
    }

    private func transition(to newState: AccountSessionState) {
        state = newState
        continuation?.yield(newState)
    }
}
#endif
