import Foundation

/// Binds a completed snapshot to the saved operation before append-only local admission.
/// The caller still owns account, deletion, claim and transaction fences.
enum ObservationReanalysisResult {
    static func decode(_ bytes: Data, matching request: ObservationReanalysisRequest) throws -> ObservationHistoryPage.Result {
        try decode(bytes, body: request.body, observationID: request.observationID, analysisID: request.analysisID,
                   sourceID: request.sourceAnalysisID, version: 2)
    }

    static func decode(_ bytes: Data, matching request: ObservationAudioReanalysisRequest) throws -> ObservationHistoryPage.Result {
        try decode(bytes, body: request.body, observationID: request.observationID, analysisID: request.analysisID,
                   sourceID: request.sourceAnalysisID, version: 4)
    }

    private static func decode(_ bytes: Data, body: Data, observationID: UUID, analysisID: UUID,
                               sourceID: UUID, version: Int) throws -> ObservationHistoryPage.Result {
        guard bytes.count <= LocalAnalysisRecord.maximumSnapshotBytes,
              let snapshot = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let input = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw ObservationHistoryError.invalidSnapshot
        }
        let ordinal = try ObservationHistoryPage.integer(snapshot["ordinal"])
        guard ordinal > 0 else { throw ObservationHistoryError.invalidSnapshot }
        // Run the complete existing result/provider/evidence validation as well as provenance checks.
        let result = try ObservationHistoryPage.snapshot(bytes, observationID: observationID.uuidString.lowercased(), ordinal: ordinal)
        guard result.version == version, result.analysisID == analysisID,
              snapshot["source_analysis_id"] as? String == sourceID.uuidString.lowercased(),
              let digest = input["request_digest"] as? String, snapshot["request_digest"] as? String == digest,
              let received = snapshot["evidence_manifest"] as? [String: Any],
              let expected = input["evidence_manifest"] as? [String: Any],
              try canonical(received) == canonical(expected) else { throw ObservationHistoryError.resultConflict }
        return result
    }

    private static func canonical(_ object: [String: Any]) throws -> Data {
        // Dictionary order is irrelevant, but array order, descriptions, nulls and exact content remain binding.
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
