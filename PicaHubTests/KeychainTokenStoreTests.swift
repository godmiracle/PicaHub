import Foundation
import Security
import Testing
@testable import PicaHub

private final class KeychainStub: KeychainAccessing, @unchecked Sendable {
    var copyStatus: OSStatus = errSecItemNotFound
    var copyResult: CFTypeRef?
    var addStatus: OSStatus = errSecSuccess
    var updateStatus: OSStatus = errSecItemNotFound
    var deleteStatus: OSStatus = errSecSuccess

    private(set) var addedAttributes: [String: Any]?
    private(set) var updatedAttributes: [String: Any]?
    private(set) var deleteCallCount = 0

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        result?.pointee = copyResult
        return copyStatus
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        addedAttributes = attributes as? [String: Any]
        return addStatus
    }

    func update(_ query: CFDictionary, attributesToUpdate: CFDictionary) -> OSStatus {
        updatedAttributes = attributesToUpdate as? [String: Any]
        return updateStatus
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        deleteCallCount += 1
        return deleteStatus
    }
}

struct KeychainTokenStoreTests {
    @Test func systemKeychainRoundTrip() throws {
        let store = KeychainTokenStore(
            service: "com.godmiracle.PicaHub.tests.\(UUID().uuidString)",
            account: "round-trip"
        )
        defer { try? store.deleteToken() }

        #expect(try store.loadToken() == nil)
        try store.saveToken("first-token")
        #expect(try store.loadToken() == "first-token")
        try store.saveToken("second-token")
        #expect(try store.loadToken() == "second-token")
        try store.deleteToken()
        #expect(try store.loadToken() == nil)
    }

    @Test func restoresStoredToken() throws {
        let keychain = KeychainStub()
        keychain.copyStatus = errSecSuccess
        keychain.copyResult = Data("stored-token".utf8) as CFData
        let store = KeychainTokenStore(keychain: keychain)

        #expect(try store.loadToken() == "stored-token")
    }

    @Test func missingTokenRestoresAsNil() throws {
        let store = KeychainTokenStore(keychain: KeychainStub())

        #expect(try store.loadToken() == nil)
    }

    @Test func saveUpdatesExistingToken() throws {
        let keychain = KeychainStub()
        keychain.updateStatus = errSecSuccess
        let store = KeychainTokenStore(keychain: keychain)

        try store.saveToken("new-token")

        #expect(keychain.updatedAttributes?[kSecValueData as String] as? Data == Data("new-token".utf8))
        #expect(keychain.addedAttributes == nil)
    }

    @Test func saveAddsMissingTokenWithDeviceOnlyAccessibility() throws {
        let keychain = KeychainStub()
        let store = KeychainTokenStore(keychain: keychain)

        try store.saveToken("new-token")

        #expect(keychain.addedAttributes?[kSecValueData as String] as? Data == Data("new-token".utf8))
        #expect(
            keychain.addedAttributes?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    @Test func emptyTokenIsRejected() {
        let store = KeychainTokenStore(keychain: KeychainStub())

        #expect(throws: TokenStoreError.invalidToken) {
            try store.saveToken("")
        }
    }

    @Test func deleteIsIdempotentWhenItemIsMissing() throws {
        let keychain = KeychainStub()
        keychain.deleteStatus = errSecItemNotFound
        let store = KeychainTokenStore(keychain: keychain)

        try store.deleteToken()

        #expect(keychain.deleteCallCount == 1)
    }

    @Test func unavailableKeychainErrorIsPreserved() {
        let keychain = KeychainStub()
        keychain.copyStatus = errSecNotAvailable
        let store = KeychainTokenStore(keychain: keychain)

        #expect(throws: TokenStoreError.unavailable(status: errSecNotAvailable)) {
            try store.loadToken()
        }
    }

    @Test func malformedStoredTokenIsRejected() {
        let keychain = KeychainStub()
        keychain.copyStatus = errSecSuccess
        keychain.copyResult = Data([0xFF]) as CFData
        let store = KeychainTokenStore(keychain: keychain)

        #expect(throws: TokenStoreError.invalidStoredData) {
            try store.loadToken()
        }
    }
}
