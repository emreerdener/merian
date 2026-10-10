import CryptoKit
import Foundation

/// Exact child-owned WAV bytes. Construction never generates identity or changes media.
struct ObservationAudioEvidenceUpload: Sendable {
    let observationID: UUID
    let analysisID: UUID
    let mediaID: UUID
    let bytes: Data

    init(observationID: UUID, analysisID: UUID, mediaID: UUID, bytes: Data) throws {
        guard Set([observationID, analysisID, mediaID]).count == 3,
              (46...2_700_000).contains(bytes.count) else { throw MerianError.invalidResponse }
        self.observationID = observationID; self.analysisID = analysisID
        self.mediaID = mediaID; self.bytes = bytes
    }

    struct Prepared: Sendable {
        let observationID: UUID
        let analysisID: UUID
        let body: Data
        let reference: ObservationHistoryAudioReference
    }

    /// The endpoint runs verification and hashing on its owned preparation task.
    func prepare() throws -> Prepared {
        try Task.checkCancellation()
        guard ObservationAudioContainer.isValid(bytes) else { throw MerianError.invalidResponse }
        let reference = ObservationHistoryAudioReference(mediaID: mediaID, contentType: "audio/wav", byteCount: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let header = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "observation_id": observationID.uuidString.lowercased(),
            "analysis_id": analysisID.uuidString.lowercased(),
            "audio": ["media_id": mediaID.uuidString.lowercased(), "content_type": "audio/wav", "byte_count": bytes.count]
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard (1...1024).contains(header.count) else { throw MerianError.invalidResponse }
        let count = UInt32(header.count)
        var body = Data([UInt8((count >> 24) & 255), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)])
        body.append(header); body.append(bytes)
        try Task.checkCancellation()
        return Prepared(observationID: observationID, analysisID: analysisID, body: body, reference: reference)
    }
}

struct ObservationAudioEvidenceUploadReceipt: Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    let reference: ObservationHistoryAudioReference

    static func decode(_ data: Data, request: ObservationAudioEvidenceUpload.Prepared) throws -> Self {
        guard data.count <= 4096,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "items"],
              try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              row["observation_id"] as? String == request.observationID.uuidString.lowercased(),
              row["analysis_id"] as? String == request.analysisID.uuidString.lowercased(),
              let items = row["items"] as? [[String: Any]], items.count == 1 else { throw MerianError.invalidResponse }
        let reference = try ObservationHistoryAudioReference.decodeManifest(["schema_version": 3, "items": items],
            observationID: request.observationID, analysisID: request.analysisID)
        guard reference == request.reference else { throw MerianError.invalidResponse }
        return Self(observationID: request.observationID, analysisID: request.analysisID, reference: reference)
    }
}
