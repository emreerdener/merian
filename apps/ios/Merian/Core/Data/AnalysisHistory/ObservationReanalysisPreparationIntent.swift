import CryptoKit
import Foundation
import SwiftData

/// Private pre-I/O ownership, never an upload or inference request.
struct ObservationReanalysisPreparationIntent: Equatable, Sendable {
    enum Action: Sendable { case hold, submit }
    let draft: ObservationReanalysisDraft
    let sourceSnapshotSHA256: String
    let action: Action

    /// Called on the preparation worker; the digest identifies exact frozen snapshot bytes.
    init(draft: ObservationReanalysisDraft, source: ObservationReanalysisSource, action: Action = .hold) throws {
        guard draft.identity.ownerID == source.ownerID, draft.identity.observationID == source.observationID,
              draft.identity.sourceAnalysisID == source.analysisID else { throw MerianError.invalidResponse }
        self.draft = draft
        self.action = action
        sourceSnapshotSHA256 = SHA256.hash(data: source.snapshot).map { String(format: "%02x", $0) }.joined()
    }

    struct Verified: Sendable {
        let pending: ObservationReanalysisPreparationIntent
        private let source: ObservationReanalysisSource

        fileprivate init(pending: ObservationReanalysisPreparationIntent, source: ObservationReanalysisSource) {
            self.pending = pending; self.source = source
        }

        @MainActor
        func validate(context: ModelContext) throws { try source.validate(context: context) }
    }

    /// Hash off MainActor, then retain the exact immutable source for the locked database comparison.
    func verified(source: ObservationReanalysisSource) throws -> Verified {
        let expected = try Self(draft: draft, source: source, action: action)
        guard expected == self else { throw MerianError.invalidResponse }
        return Verified(pending: self, source: source)
    }

    private init(draft: ObservationReanalysisDraft, digest: String, action: Action) {
        self.draft = draft; sourceSnapshotSHA256 = digest; self.action = action
    }

    var ready: ObservationReanalysisPersistence.DraftState {
        action == .submit ? .submitted(ObservationReanalysisSubmissionIntent(preparation: self)) : .draft(draft)
    }

    func readyData() throws -> Data {
        try action == .submit ? ObservationReanalysisSubmissionIntent(preparation: self).storedData() : draft.storedData()
    }

    func storedData() throws -> Data {
        var row: [String: Any] = ["version": action == .submit ? 4 : 3, "phase": "files_pending",
            "draft": try JSONSerialization.jsonObject(with: draft.storedData()), "source_snapshot_sha256": sourceSnapshotSHA256]
        if action == .submit { row["requested_action"] = "admit" }
        let data = try JSONSerialization.data(withJSONObject: row,
            options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 1_048_576 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
              row["phase"] as? String == "files_pending", let body = row["draft"] as? [String: Any],
              let digest = row["source_snapshot_sha256"] as? String, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw MerianError.invalidResponse }
        let keys: Set<String> = ["version", "phase", "draft", "source_snapshot_sha256"]
        let action: Action
        if version.doubleValue == 3, Set(row.keys) == keys { action = .hold } else if
            version.doubleValue == 4, Set(row.keys) == keys.union(["requested_action"]), row["requested_action"] as? String == "admit" {
            action = .submit
        } else { throw MerianError.invalidResponse }
        return try Self(draft: .decode(JSONSerialization.data(withJSONObject: body)), digest: digest, action: action)
    }
}
