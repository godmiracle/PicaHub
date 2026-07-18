import Foundation
import Security

protocol KeychainAccessing: Sendable {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, attributesToUpdate: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemKeychain: KeychainAccessing {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func update(_ query: CFDictionary, attributesToUpdate: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributesToUpdate)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

struct KeychainTokenStore<Keychain: KeychainAccessing>: TokenStore {
    private let service: String
    private let account: String
    private let keychain: Keychain

    init(
        service: String = "com.godmiracle.PicaHub.session",
        account: String = "picacomic-token",
        keychain: Keychain
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
    }

    func loadToken() throws -> String? {
        var result: CFTypeRef?
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = keychain.copyMatching(query as CFDictionary, result: &result)
        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let token = String(data: data, encoding: .utf8),
                !token.isEmpty
            else {
                throw TokenStoreError.invalidStoredData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.unavailable(status: status)
        }
    }

    func saveToken(_ token: String) throws {
        guard !token.isEmpty else {
            throw TokenStoreError.invalidToken
        }
        let tokenData = Data(token.utf8)
        let updateAttributes = [kSecValueData as String: tokenData]
        let updateStatus = keychain.update(
            baseQuery as CFDictionary,
            attributesToUpdate: updateAttributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery
            attributes[kSecValueData as String] = tokenData
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = keychain.add(attributes as CFDictionary)
            guard addStatus == errSecSuccess else {
                throw TokenStoreError.unavailable(status: addStatus)
            }
        default:
            throw TokenStoreError.unavailable(status: updateStatus)
        }
    }

    func deleteToken() throws {
        let status = keychain.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.unavailable(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension KeychainTokenStore where Keychain == SystemKeychain {
    init(
        service: String = "com.godmiracle.PicaHub.session",
        account: String = "picacomic-token"
    ) {
        self.init(service: service, account: account, keychain: SystemKeychain())
    }
}
