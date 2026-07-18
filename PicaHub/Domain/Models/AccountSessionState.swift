import Foundation

enum AccountSessionState: Sendable, Equatable {
    case restoring
    case unauthenticated
    case authenticating(email: String)
    case authenticated
    case failed(AccountSessionFailure)
}

struct AccountSessionFailure: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case validation
        case authentication
        case network
        case secureStorage
        case unknown
    }

    let kind: Kind
    let message: String
    let email: String?
    let isRetryable: Bool
}
