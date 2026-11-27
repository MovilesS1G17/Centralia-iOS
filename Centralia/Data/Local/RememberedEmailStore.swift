import Foundation
import Security

/// "Remember my email" on the sign-in screen (Sprint 3 · local storage).
/// iOS keeps it in the Keychain (Gustavo); Android keeps it in DataStore.
/// Only the email is stored, never the password, and it survives sign-out on
/// purpose: that is when the user needs it.
nonisolated protocol RememberedEmailStoring: Sendable {
    func email() -> String?
    func remember(_ email: String)
    func forget()
}

/// Local storage with the **Keychain**.
///
/// Why the Keychain and not UserDefaults (which the profile copy uses):
/// an email identifies the person, and the Keychain is encrypted by the
/// system, isn't included in unencrypted backups and can't be read by other
/// apps. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps it on this
/// phone only. The session token already lives here
/// (`KeychainAuthenticationTokenStore`), under a different account.
nonisolated struct KeychainRememberedEmailStore: RememberedEmailStoring {
    private let service: String
    private let account = "centralia.login.remembered-email"

    init(service: String = Bundle.main.bundleIdentifier ?? "co.edu.uniandes.centralia") {
        self.service = service
    }

    func email() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remember(_ email: String) {
        guard let data = email.data(using: .utf8) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    func forget() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Used by the mock build, previews and tests.
nonisolated final class InMemoryRememberedEmailStore: RememberedEmailStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: String?

    init(_ saved: String? = nil) { self.saved = saved }

    func email() -> String? { lock.withLock { saved } }
    func remember(_ email: String) { lock.withLock { saved = email } }
    func forget() { lock.withLock { saved = nil } }
}
