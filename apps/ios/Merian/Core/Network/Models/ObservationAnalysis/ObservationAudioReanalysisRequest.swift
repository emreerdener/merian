import CryptoKit
import Foundation

/// Separate schema-3 input. Saved photo schema-2 parsing and bytes remain unchanged.
/// This metadata value grants neither upload readiness nor dispatch permission.
struct ObservationAudioReanalysisRequest: Equatable, Sendable {
    enum Evidence: Equatable, Sendable {
        case audio(ObservationHistoryAudioReference)
        case description(String)
    }

    let observationID: UUID
    let analysisID: UUID
    let sourceAnalysisID: UUID
    let evidence: [Evidence]
    let body: Data
    let requestDigest: String

    init(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID, evidence: [Evidence]) throws {
        guard Set([observationID, analysisID, sourceAnalysisID]).count == 3,
              (1...64).contains(evidence.count) else { throw MerianError.invalidResponse }
        let manifest = Self.manifest(evidence)
        let audio = try ObservationHistoryAudioReference.decodeManifest(manifest,
            observationID: observationID, analysisID: analysisID)
        guard audio.mediaID != sourceAnalysisID else { throw MerianError.invalidResponse }
        var row: [String: Any] = [
            "schema_version": 3, "observation_id": observationID.uuidString.lowercased(),
            "analysis_id": analysisID.uuidString.lowercased(), "source_analysis_id": sourceAnalysisID.uuidString.lowercased(),
            "entitlement_protocol": 3, "identification_protocol": 6, "history_protocol": 9,
            "expected_processor_permission": "google_gemini", "evidence_manifest": manifest
        ]
        row["request_digest"] = try Self.digest(row)
        try self.init(savedBody: Self.canonical(row))
    }

    init(savedBody: Data) throws {
        guard savedBody.count <= 1_044_480,
              let row = try JSONSerialization.jsonObject(with: savedBody) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "source_analysis_id", "request_digest",
                                "evidence_manifest", "entitlement_protocol", "identification_protocol", "history_protocol",
                                "expected_processor_permission"],
              try ObservationHistoryPage.integer(row["schema_version"]) == 3,
              try ObservationHistoryPage.integer(row["entitlement_protocol"]) == 3,
              try ObservationHistoryPage.integer(row["identification_protocol"]) == 6,
              try ObservationHistoryPage.integer(row["history_protocol"]) == 9,
              row["expected_processor_permission"] as? String == "google_gemini" else { throw MerianError.invalidResponse }
        let observation = try ObservationHistoryPage.uuid(row["observation_id"])
        let analysis = try ObservationHistoryPage.uuid(row["analysis_id"])
        let source = try ObservationHistoryPage.uuid(row["source_analysis_id"])
        guard Set([observation, analysis, source]).count == 3 else { throw MerianError.invalidResponse }
        var unsigned = row
        unsigned.removeValue(forKey: "request_digest")
        guard let digest = row["request_digest"] as? String, digest == (try Self.digest(unsigned)) else {
            throw MerianError.invalidResponse
        }
        let audio = try ObservationHistoryAudioReference.decodeManifest(row["evidence_manifest"],
            observationID: observation, analysisID: analysis)
        guard audio.mediaID != source,
              let manifest = row["evidence_manifest"] as? [String: Any],
              let items = manifest["items"] as? [[String: Any]] else { throw MerianError.invalidResponse }
        self.evidence = try items.map { item in
            if item["kind"] as? String == "audio" { return .audio(audio) }
            guard let text = item["text"] as? String else { throw MerianError.invalidResponse }
            return .description(text)
        }
        self.observationID = observation; self.analysisID = analysis; self.sourceAnalysisID = source
        self.body = savedBody; self.requestDigest = digest
    }

    static func manifest(_ evidence: [Evidence]) -> [String: Any] {
        ["schema_version": 3, "items": evidence.map { item -> [String: Any] in
            switch item {
            case let .description(text): return ["kind": "description", "text": text]
            case let .audio(audio):
                return ["kind": "audio", "media_id": audio.mediaID.uuidString.lowercased(), "content_type": audio.contentType,
                        "byte_count": audio.byteCount, "sha256": audio.sha256]
            }
        }]
    }

    private static func canonical(_ row: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private static func digest(_ row: [String: Any]) throws -> String {
        SHA256.hash(data: try canonical(row)).map { String(format: "%02x", $0) }.joined()
    }
}
