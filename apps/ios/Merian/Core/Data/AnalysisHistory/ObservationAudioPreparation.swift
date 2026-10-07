import CryptoKit
import Foundation
import SwiftData

/// Held audio preparation only. No processor, request, funding or dispatch authority.
struct ObservationAudioPreparation: Equatable, Sendable {
    enum Phase: String, Sendable { case pending = "files_pending", ready = "files_ready" }
    let identity: OfflineQueueWork.Reanalysis
    let evidence: [ObservationAudioReanalysisRequest.Evidence]
    let audio: ObservationHistoryAudioReference
    let sourceSnapshotSHA256: String

    var path: String { "ReanalysisQueue/" + identity.analysisID.uuidString.lowercased() + "/" + audio.mediaID.uuidString.lowercased() + ".wav" }
    var media: [SerializedMediaItem] { [.audio(.documents(path))] }

    init(identity: OfflineQueueWork.Reanalysis, evidence: [ObservationAudioReanalysisRequest.Evidence], source: ObservationReanalysisSource) throws {
        guard identity.ownerID == source.ownerID, identity.observationID == source.observationID,
              identity.sourceAnalysisID == source.analysisID,
              !evidence.contains(where: { item in
                  if case let .audio(audio) = item { return source.photos.contains { $0.mediaID == audio.mediaID } }
                  return false
              }) else { throw MerianError.invalidResponse }
        try self.init(identity: identity, evidence: evidence,
            digest: SHA256.hash(data: source.snapshot).map { String(format: "%02x", $0) }.joined())
    }

    private init(identity: OfflineQueueWork.Reanalysis, evidence: [ObservationAudioReanalysisRequest.Evidence], digest: String) throws {
        guard Set([identity.observationID, identity.analysisID, identity.sourceAnalysisID]).count == 3,
              (1...64).contains(evidence.count), digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw MerianError.invalidResponse }
        let audio = try ObservationHistoryAudioReference.decodeManifest(ObservationAudioReanalysisRequest.manifest(evidence),
            observationID: identity.observationID, analysisID: identity.analysisID)
        guard audio.mediaID != identity.sourceAnalysisID, audio.mediaID != identity.ownerID else { throw MerianError.invalidResponse }
        self.identity = identity; self.evidence = evidence; self.audio = audio; sourceSnapshotSHA256 = digest
    }

    struct Verified: Sendable {
        let preparation: ObservationAudioPreparation
        private let source: ObservationReanalysisSource
        fileprivate init(_ preparation: ObservationAudioPreparation, source: ObservationReanalysisSource) {
            self.preparation = preparation; self.source = source
        }
        @MainActor func validate(context: ModelContext) throws { try source.validate(context: context) }
    }

    /// Compute off-main, retaining the original bytes for fresh transaction validation.
    func verified(source: ObservationReanalysisSource) throws -> Verified {
        guard try Self(identity: identity, evidence: evidence, source: source) == self else { throw MerianError.invalidResponse }
        return Verified(self, source: source)
    }

    func storedData(phase: Phase) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "kind": "audio_preparation", "phase": phase.rawValue, "requested_action": "hold",
            "owner_id": identity.ownerID.uuidString.lowercased(), "observation_id": identity.observationID.uuidString.lowercased(),
            "analysis_id": identity.analysisID.uuidString.lowercased(), "source_analysis_id": identity.sourceAnalysisID.uuidString.lowercased(),
            "source_snapshot_sha256": sourceSnapshotSHA256, "evidence_manifest": ObservationAudioReanalysisRequest.manifest(evidence)
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 1_048_576 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> (preparation: Self, phase: Phase) {
        guard data.count <= 1_048_576, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "kind", "phase", "requested_action", "owner_id", "observation_id", "analysis_id",
                                "source_analysis_id", "source_snapshot_sha256", "evidence_manifest"],
              try ObservationHistoryPage.integer(row["version"]) == 1, row["kind"] as? String == "audio_preparation",
              row["requested_action"] as? String == "hold", let raw = row["phase"] as? String, let phase = Phase(rawValue: raw),
              let digest = row["source_snapshot_sha256"] as? String else { throw MerianError.invalidResponse }
        let identity = try OfflineQueueWork.Reanalysis(observationID: ObservationHistoryPage.uuid(row["observation_id"]),
            sourceAnalysisID: ObservationHistoryPage.uuid(row["source_analysis_id"]), analysisID: ObservationHistoryPage.uuid(row["analysis_id"]),
            ownerID: ObservationHistoryPage.uuid(row["owner_id"]))
        let audio = try ObservationHistoryAudioReference.decodeManifest(row["evidence_manifest"],
            observationID: identity.observationID, analysisID: identity.analysisID)
        guard let manifest = row["evidence_manifest"] as? [String: Any], let items = manifest["items"] as? [[String: Any]] else {
            throw MerianError.invalidResponse
        }
        let evidence: [ObservationAudioReanalysisRequest.Evidence] = try items.map { item in
            if item["kind"] as? String == "audio" { return .audio(audio) }
            guard let text = item["text"] as? String else { throw MerianError.invalidResponse }
            return .description(text)
        }
        return (try Self(identity: identity, evidence: evidence, digest: digest), phase)
    }
}
