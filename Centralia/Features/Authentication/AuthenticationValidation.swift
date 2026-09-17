import Foundation

enum AuthenticationValidation {
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func emailError(for email: String) -> String? {
        let normalized = normalizedEmail(email)
        let components = normalized.split(separator: "@", omittingEmptySubsequences: false)

        guard components.count == 2,
              !components[0].isEmpty,
              components[1].contains("."),
              !components[1].hasPrefix("."),
              !components[1].hasSuffix(".") else {
            return "Enter a valid email address."
        }

        return nil
    }

    static func passwordError(for password: String) -> String? {
        password.count >= 8 ? nil : "Use at least 8 characters."
    }
}
