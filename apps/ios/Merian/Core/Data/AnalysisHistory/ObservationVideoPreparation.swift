import CryptoKit
import Foundation
import SwiftData

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
    /// Retained clip plus ordered derived frames; no legacy inferenceImagePaths.
    var media: [SerializedMediaItem] {
        let source = StoredMediaReference.documents(files[0].path)
        let audio = request.manifest.provenance.audio == nil ? nil : StoredMediaReference.documents(files[files.count - 1].path)
        // V58 entries store a video path only; preserve the companion as its own entry.
        // The immutable manifest retains the source-to-audio relationship.
        return [.video(.init(video: source))] + files[1...5].map { .image(.documents($0.path)) } + (audio.map { [.audio($0)] } ?? [])
    }
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

    /// Explicit new video evidence is bound to the immutable result the user opened.
    /// This does not establish current account authority until the owner validates its lease.
    init(request: ObservationVideoReanalysisRequest, source: ObservationReanalysisSource) throws {
        guard request.observationID == source.observationID, request.sourceAnalysisID == source.analysisID else {
            throw MerianError.invalidResponse
        }
        try self.init(ownerID: source.ownerID, request: request,
                      sourceSnapshotSHA256: SHA256.hash(data: source.snapshot).map { String(format: "%02x", $0) }.joined())
        let historicalMedia = Set(source.photos.map(\.mediaID) + (source.audio.map { [$0.mediaID] } ?? []))
        guard !historicalMedia.contains(request.analysisID),
              files.allSatisfy({ !historicalMedia.contains($0.artifact.mediaID) }) else { throw MerianError.invalidResponse }
    }

    struct Verified: Sendable {
        let preparation: ObservationVideoPreparation
        private let source: ObservationReanalysisSource
        fileprivate init(_ preparation: ObservationVideoPreparation, source: ObservationReanalysisSource) {
            self.preparation = preparation; self.source = source
        }
        /// Caller owns the shared persistence lock; do not acquire it recursively.
        @MainActor func validate(context: ModelContext) throws { try source.validate(context: context) }
        @MainActor func validate(container: ModelContainer) throws { try source.validate(container: container) }
    }

    /// Reconstruct from the frozen source, not the persisted digest alone. No database writes.
    func verified(source: ObservationReanalysisSource) throws -> Verified {
        guard try Self(request: request, source: source) == self else { throw MerianError.invalidResponse }
        return Verified(self, source: source)
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

    /// Routing fence only, never video eligibility. Reject even an unsupported or
    /// damaged video phase before a legacy photo reader can attempt restoration.
    static func requireNonVideo(_ data: Data) throws {
        guard data.count <= maximumStoredBytes else { throw MerianError.invalidResponse }
        if let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let kind = row["kind"] as? String,
           ["video_preparation", ObservationVideoSourceReservationWork.kind, ObservationVideoUploadWork.kind, ObservationVideoExecutionWork.kind].contains(kind) {
            throw MerianError.invalidResponse
        }
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
