import Foundation

/// Closed local metadata only. Neither decoding nor files_ready proves storage or admission.
struct ObservationVideoPreparation: Equatable, Sendable {
    enum Phase: String, Sendable { case pending = "files_pending", ready = "files_ready" }
    struct File: Equatable, Sendable {
        let artifact: ObservationVideoProvenance.Artifact
        let path: String
    }
    let identity: OfflineQueueWork.Reanalysis
    let request: ObservationVideoReanalysisRequest
    let sourceSnapshotSHA256: String
    let files: [File]
    static let maximumStoredBytes = 2_097_152

    init(ownerID: UUID, request: ObservationVideoReanalysisRequest, sourceSnapshotSHA256: String) throws {
        guard sourceSnapshotSHA256.utf8.count == 64,
              sourceSnapshotSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw MerianError.invalidResponse
        }
        let identity = OfflineQueueWork.Reanalysis(observationID: request.observationID, sourceAnalysisID: request.sourceAnalysisID,
                                                   analysisID: request.analysisID, ownerID: ownerID)
        let graph = request.manifest.provenance
        let artifacts = [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
        guard !artifacts.contains(where: { $0.mediaID == ownerID }),
              ![request.observationID, request.analysisID, request.sourceAnalysisID].contains(ownerID) else { throw MerianError.invalidResponse }
        self.identity = identity; self.request = request; self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        files = try artifacts.map { artifact in
            let suffix: String
            switch artifact.contentType {
            case "video/mp4": suffix = "mp4"
            case "image/webp": suffix = "webp"
            case "image/jpeg": suffix = "jpg"
            case "audio/wav": suffix = "wav"
            default: throw MerianError.invalidResponse
            }
            return File(artifact: artifact, path: "ReanalysisQueue/" + identity.analysisID.uuidString.lowercased()
                        + "/" + artifact.mediaID.uuidString.lowercased() + "." + suffix)
        }
    }

    func storedData(phase: Phase) throws -> Data {
        guard let body = String(data: request.body, encoding: .utf8) else { throw MerianError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "kind": "video_preparation", "phase": phase.rawValue,
            "owner_id": identity.ownerID.uuidString.lowercased(), "source_snapshot_sha256": sourceSnapshotSHA256,
            "request_body": body, "files": files.map { ["media_id": $0.artifact.mediaID.uuidString.lowercased(), "path": $0.path] }
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumStoredBytes else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> (preparation: Self, phase: Phase) {
        guard !data.isEmpty, data.count <= maximumStoredBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: [
            "version", "kind", "phase", "owner_id", "source_snapshot_sha256", "request_body", "files"
        ])
        guard try ObservationHistoryPage.integer(row["version"]) == 1, row["kind"] as? String == "video_preparation",
              let raw = row["phase"] as? String, let phase = Phase(rawValue: raw),
              let digest = row["source_snapshot_sha256"] as? String,
              let body = row["request_body"] as? String,
              let files = row["files"] as? [[String: Any]], (6...7).contains(files.count) else { throw MerianError.invalidResponse }
        let request = try ObservationVideoReanalysisRequest(savedBody: Data(body.utf8))
        let preparation = try Self(ownerID: ObservationHistoryPage.uuid(row["owner_id"]), request: request, sourceSnapshotSHA256: digest)
        guard files.count == preparation.files.count else { throw MerianError.invalidResponse }
        for (saved, expected) in zip(files, preparation.files) {
            let file = try ObservationHistoryPage.object(saved, keys: ["media_id", "path"])
            guard file["media_id"] as? String == expected.artifact.mediaID.uuidString.lowercased(),
                  file["path"] as? String == expected.path else { throw MerianError.invalidResponse }
        }
        return (preparation, phase)
    }
}
