import Foundation

/// Wire-proof syntax and timestamp admission, not Keychain or deletion authority.
enum AccountDeletionRecoveryValidation {
    static func isValidCapability(_ value: String) -> Bool {
        value.utf8.count == 43 && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) ||
                ($0.value >= 65 && $0.value <= 90) ||
                ($0.value >= 97 && $0.value <= 122) ||
                $0.value == 95 || $0.value == 45
        }
    }

    static func isValidExpiry(
        _ value: String?,
        now: () -> Date = { Date() }
    ) -> Bool {
        guard let date = recoveryDate(value) else {
            return false
        }
        return date > now().addingTimeInterval(-5 * 60)
    }

    static func isValidTimestamp(_ value: String?) -> Bool {
        recoveryDate(value) != nil
    }

    private static func recoveryDate(_ value: String?) -> Date? {
        guard let value,
              value.utf8.count >= 20,
              value.utf8.count <= 40 else {
            return nil
        }
        return DateUtilities.iso8601FractionalFormatter.date(from: value)
            ?? DateUtilities.iso8601Formatter.date(from: value)
    }
}
