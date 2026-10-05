import CryptoKit
import Foundation
import SwiftData

/// Private pre-I/O ownership, never an upload or inference request.
struct ObservationReanalysisPreparationIntent: Equatable, Sendable {
    let draft: ObservationReanalysisDraft
    let sourceSnapshotSHA256: String

    /// Called on the preparation worker; the digest identifies exact frozen snapshot bytes.
    init(draft: ObservationReanalysisDraft, source: ObservationReanalysisSource) throws {
        guard draft.identity.ownerID == source.ownerID, draft.identity.observationID == source.observationID,
              draft.identity.sourceAnalysisID == source.analysisID else { throw MerianError.invalidResponse }
        self.draft = draft
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
        let expected = try Self(draft: draft, source: source)
        guard expected == self else { throw MerianError.invalidResponse }
        return Verified(pending: self, source: source)
    }

    private init(draft: ObservationReanalysisDraft, digest: String) { self.draft = draft; sourceSnapshotSHA256 = digest }

    func storedData() throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: ["version": 3, "phase": "files_pending",
            "draft": JSONSerialization.jsonObject(with: draft.storedData()), "source_snapshot_sha256": sourceSnapshotSHA256],
            options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 1_048_576 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "phase", "draft", "source_snapshot_sha256"],
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 3,
              row["phase"] as? String == "files_pending", let body = row["draft"] as? [String: Any],
              let digest = row["source_snapshot_sha256"] as? String, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw MerianError.invalidResponse }
        return try Self(draft: .decode(JSONSerialization.data(withJSONObject: body)), digest: digest)
    }
}
