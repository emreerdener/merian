import CryptoKit
import Foundation

enum PurchasePrincipalCapabilityPolicy {
    static func fingerprint(_ capability: Data) -> String {
        SHA256.hash(data: capability)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func isValidFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

enum PurchasePrincipalBindingIntentPolicy {
    // JSON crosses Deno/JavaScript before Postgres. Keep the durable counter in
    // the exact-integer range shared by all three runtimes.
    static let maximum = Int64(9_007_199_254_740_991)

    static func next(after current: Int64) throws -> Int64 {
        guard current >= 0, current < maximum else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return current + 1
    }
}

enum PurchasePrincipalCompatibilityPolicy {
    static func allowsLegacyFallback(hasStableActivation: Bool) -> Bool {
        !hasStableActivation
    }
}

enum PurchasePrincipalTimestampPolicy {
    static func isValidServerTimestamp(_ value: String) -> Bool {
        guard (20...40).contains(value.utf8.count) else { return false }
        return DateUtilities.iso8601FractionalFormatter.date(from: value) != nil
            || DateUtilities.iso8601Formatter.date(from: value) != nil
    }
}

enum PurchasePrincipalSecretPolicy {
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func isValidRotationSecret(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
        ) != nil
    }
}
