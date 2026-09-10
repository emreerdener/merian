import CryptoKit
import Foundation

enum StoreRecoveryPrivacyPolicy {
    private static let allowlistedErrorDomains: Set<String> = [
        "NSCocoaErrorDomain",
        "NSMachErrorDomain",
        "NSOSStatusErrorDomain",
        "NSPOSIXErrorDomain",
        "NSSQLiteErrorDomain",
        "NSURLErrorDomain",
        "SwiftData.SwiftDataError",
        "app.merian.model-container",
        "app.merian.objc-exception"
    ]

    static func fingerprint(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return fingerprint(Data(text.utf8))
    }

    static func sanitizedErrorText(_ text: String?) -> String? {
        text.flatMap(labeledFingerprint)
    }

    static func sanitizedErrorDomain(_ domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }
        guard !allowlistedErrorDomains.contains(trimmed) else { return trimmed }
        return labeledFingerprint(trimmed)
    }

    static func sanitizedMetadataString(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }
        return labeledFingerprint(trimmed)
    }

    private static func labeledFingerprint(_ text: String) -> String {
        "sha256:\(fingerprint(Data(text.utf8)))"
    }

    private static func fingerprint(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func stableDescription(from value: Any?) -> String {
        guard let value else { return "nil" }

        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let data as Data:
            return "data:\(fingerprint(data))"
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let values as [Any]:
            return "[" + values.map(stableDescription(from:)).joined(separator: ",") + "]"
        case let strings as [String]:
            return "[" + strings.sorted().joined(separator: ",") + "]"
        case let set as NSSet:
            return "[" + set.allObjects.map(stableDescription(from:)).sorted().joined(separator: ",") + "]"
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().map { key in
                "\(key)=\(stableDescription(from: dictionary[key]))"
            }.joined(separator: ";")
        default:
            return String(describing: value)
        }
    }
}
