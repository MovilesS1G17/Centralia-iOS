import Foundation
import Security

protocol AuthenticationTokenStore {
    func accessToken() throws -> String?
    func save(accessToken: String) throws
    func save(accessToken: String, verifiedUser: AuthenticatedUser) throws
    func verifiedUser(forAccessToken accessToken: String) throws -> AuthenticatedUser?
    func clearAccessToken() throws
}

extension AuthenticationTokenStore {
    func save(accessToken: String, verifiedUser _: AuthenticatedUser) throws {
        try save(accessToken: accessToken)
    }

    func verifiedUser(forAccessToken _: String) throws -> AuthenticatedUser? { nil }
}

struct KeychainAuthenticationTokenStore: AuthenticationTokenStore {
    private struct StoredSession: Codable {
        let accessToken: String
        let user: AuthenticatedUser
    }

    private let service: String
    private let account = "centralia.authentication.access-token"

    init(service: String = Bundle.main.bundleIdentifier ?? "co.edu.uniandes.centralia") {
        self.service = service
    }

    func accessToken() throws -> String? {
        guard let data = try read() else { return nil }
        if data.first == UInt8(ascii: "{") {
            return try decodeSession(data).accessToken
        }
        // Previous versions wrote the bearer token as a UTF-8 string.
        guard let token = String(data: data, encoding: .utf8) else {
            throw AuthenticationError.secureStorageUnavailable
        }
        return token
    }

    func verifiedUser(forAccessToken accessToken: String) throws -> AuthenticatedUser? {
        guard let data = try read(), data.first == UInt8(ascii: "{") else { return nil }
        let session = try decodeSession(data)
        return session.accessToken == accessToken ? session.user : nil
    }

    private func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthenticationError.secureStorageUnavailable
        }
        return data
    }

    func save(accessToken: String) throws {
        try write(Data(accessToken.utf8))
    }

    func save(accessToken: String, verifiedUser: AuthenticatedUser) throws {
        let data = try JSONEncoder().encode(StoredSession(accessToken: accessToken, user: verifiedUser))
        try write(data)
    }

    private func write(_ data: Data) throws {
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

    private func decodeSession(_ data: Data) throws -> StoredSession {
        do {
            return try JSONDecoder().decode(StoredSession.self, from: data)
        } catch {
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
