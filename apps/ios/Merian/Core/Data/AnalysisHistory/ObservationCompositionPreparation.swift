import CryptoKit
import Foundation
import SwiftData

/// Local preparation only. A ready cohort is not a source reservation, upload
/// grant, funding decision or execution permit. Existing generations are closed.
struct ObservationCompositionPreparation: Equatable, Sendable {
    enum Phase: String, Sendable { case pending = "files_pending", ready = "files_ready" }
    struct File: Equatable, Sendable {
        let artifact: ObservationCompositionManifest.Artifact
        let path: String
    }
    let identity: OfflineQueueWork.Reanalysis
    let request: ObservationCompositionReanalysisRequest
    let sourceSnapshotSHA256: String
    let files: [File]
    static let maximumStoredBytes = 2_097_152

    var media: [SerializedMediaItem] {
        files.map { file in
            let reference = StoredMediaReference.documents(file.path)
            switch file.artifact.contentType {
            case "video/mp4": return .video(.init(video: reference))
            case "audio/wav": return .audio(reference)
            default: return .image(reference)
            }
        }
    }
    var coverPath: String? { files.first { $0.artifact.contentType.hasPrefix("image/") }?.path }

    init(ownerID: UUID, request: ObservationCompositionReanalysisRequest, sourceSnapshotSHA256: String) throws {
        guard sourceSnapshotSHA256.utf8.count == 64,
              sourceSnapshotSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              ![request.observationID, request.analysisID, request.sourceAnalysisID].contains(ownerID) else { throw MerianError.invalidResponse }
        let identity = OfflineQueueWork.Reanalysis(observationID: request.observationID, sourceAnalysisID: request.sourceAnalysisID,
            analysisID: request.analysisID, ownerID: ownerID)
        let artifacts = request.manifest.items.flatMap { item -> [ObservationCompositionManifest.Artifact] in
            switch item {
            case let .image(value), let .audio(value): return [value]
            case let .video(graph): return [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
            case .description: return []
            }
        }
        guard !artifacts.isEmpty, artifacts.allSatisfy({ $0.mediaID != ownerID }) else { throw MerianError.invalidResponse }
        self.identity = identity; self.request = request; self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        files = try artifacts.map { artifact in
            let suffix: String
            switch artifact.contentType {
            case "video/mp4": suffix = "mp4"
            case "image/webp": suffix = "webp"
            case "image/jpeg": suffix = "jpg"
            case "image/png": suffix = "png"
            case "audio/wav": suffix = "wav"
            default: throw MerianError.invalidResponse
            }
            return File(artifact: artifact, path: "ReanalysisQueue/" + identity.analysisID.uuidString.lowercased()
                + "/" + artifact.mediaID.uuidString.lowercased() + "." + suffix)
        }
    }

    init(request: ObservationCompositionReanalysisRequest, source: ObservationReanalysisSource) throws {
        guard request.observationID == source.observationID, request.sourceAnalysisID == source.analysisID else { throw MerianError.invalidResponse }
        try self.init(ownerID: source.ownerID, request: request,
            sourceSnapshotSHA256: SHA256.hash(data: source.snapshot).map { String(format: "%02x", $0) }.joined())
        guard !source.artifactIDs.contains(request.analysisID),
              files.allSatisfy({ !source.artifactIDs.contains($0.artifact.mediaID) }) else { throw MerianError.invalidResponse }
    }

    struct Verified: Sendable {
        let preparation: ObservationCompositionPreparation
        private let source: ObservationReanalysisSource
        fileprivate init(_ preparation: ObservationCompositionPreparation, source: ObservationReanalysisSource) {
            self.preparation = preparation; self.source = source
        }
        @MainActor func validate(context: ModelContext) throws { try source.validate(context: context) }
        @MainActor func validate(container: ModelContainer) throws { try source.validate(container: container) }
    }

    func verified(source: ObservationReanalysisSource) throws -> Verified {
        guard try Self(request: request, source: source) == self else { throw MerianError.invalidResponse }
        return Verified(self, source: source)
    }

    func storedData(phase: Phase) throws -> Data {
        guard let body = String(data: request.body, encoding: .utf8) else { throw MerianError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "kind": "composition_preparation", "phase": phase.rawValue,
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
        guard try ObservationHistoryPage.integer(row["version"]) == 1, row["kind"] as? String == "composition_preparation",
              let raw = row["phase"] as? String, let phase = Phase(rawValue: raw),
              let digest = row["source_snapshot_sha256"] as? String, let body = row["request_body"] as? String,
              let files = row["files"] as? [[String: Any]] else { throw MerianError.invalidResponse }
        let request = try ObservationCompositionReanalysisRequest(savedBody: Data(body.utf8))
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
