import Foundation

enum AuthenticationValidation {
    static let weakPassword = "Use at least 8 characters, with letters and numbers."
    static let commonPassword = "This password is too common. Choose another one."
    static let passwordHint = "8+ characters, letters and numbers"

    static let commonPasswords: Set<String> = [
        "password1", "password12", "password123", "password1234", "passw0rd", "qwerty123", "qwerty1234",
        "abc12345", "abcd1234", "1q2w3e4r", "1qaz2wsx", "iloveyou1", "admin123", "welcome1", "welcome123",
        "letmein1", "monkey123", "dragon123", "football1", "baseball1", "sunshine1", "princess1", "123456789a",
        "a123456789", "contraseña1", "contrasena1", "contrasena123", "centralia1", "centralia123"
    ]

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
        let length = password.utf16.count
        if length < 8 || length > 128 ||
            !password.contains(where: { $0.isLetter }) ||
            !password.contains(where: isDecimalDigit) {
            return weakPassword
        }
        if commonPasswords.contains(password.lowercased()) {
            return commonPassword
        }
        return nil
    }

    nonisolated private static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 &&
            character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }
}
