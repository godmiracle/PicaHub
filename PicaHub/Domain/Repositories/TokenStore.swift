import Foundation

protocol TokenStore: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

enum TokenStoreError: Error, Sendable, Equatable {
    case invalidToken
    case invalidStoredData
    case unavailable(status: Int32)
}
