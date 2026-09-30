import Foundation
import Security

protocol AuthenticationTokenStore {
    func accessToken() throws -> String?
    func save(accessToken: String) throws
    func clearAccessToken() throws
}

struct KeychainAuthenticationTokenStore: AuthenticationTokenStore {
    private let service: String
    private let account = "centralia.authentication.access-token"

    init(service: String = Bundle.main.bundleIdentifier ?? "co.edu.uniandes.centralia") {
        self.service = service
    }

    func accessToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw AuthenticationError.secureStorageUnavailable
        }
        return token
    }

    func save(accessToken: String) throws {
        guard let data = accessToken.data(using: .utf8) else {
            throw AuthenticationError.secureStorageUnavailable
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw AuthenticationError.secureStorageUnavailable
        }

        let update = [kSecValueData as String: data]
        guard SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecSuccess else {
            throw AuthenticationError.secureStorageUnavailable
        }
    }

    func clearAccessToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.secureStorageUnavailable
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
