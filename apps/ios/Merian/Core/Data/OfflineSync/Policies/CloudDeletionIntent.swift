import Foundation

/// Local provenance only. The server still verifies scan ownership, and this
/// envelope never authorizes deletion of retained observation history.
struct CloudDeletionIntent: Codable, Equatable, Sendable {
    enum Origin: String, Codable, Sendable {
        case explicitUserDeletion
        case reanalysisReplacement
        case nonBiologicalRetention
    }

    static let legacyHoldCode = "cloud_deletion_intent_requires_review"
    let version: Int
    let scanID: String
    let requestingAccountID: UUID
    let origin: Origin

    init(scanID: String, requestingAccountID: UUID, origin: Origin) {
        version = 1
        self.scanID = scanID
        self.requestingAccountID = requestingAccountID
        self.origin = origin
    }

    func storedJSON() throws -> String {
        guard let text = String(data: try JSONEncoder().encode(self), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func restoring(_ text: String?, scanID: String) -> Self? {
        guard let text, text.utf8.count <= 2_048,
              let value = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)),
              value.version == 1, value.scanID == scanID else { return nil }
        return value
    }
}
