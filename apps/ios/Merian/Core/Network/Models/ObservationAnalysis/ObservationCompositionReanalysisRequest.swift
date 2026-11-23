import CryptoKit
import Foundation

/// One immutable toolbar composition. Preparation does not authorize admission,
/// upload, quota use or execution; those require the composition's durable owner.
struct ObservationCompositionReanalysisRequest: Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    let sourceAnalysisID: UUID
    let manifest: ObservationCompositionManifest
    let body: Data
    let requestDigest: String

    init(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID, manifestBytes: Data) throws {
        let manifest = try ObservationCompositionManifest(data: manifestBytes, observationID: observationID,
            analysisID: analysisID, sourceAnalysisID: sourceAnalysisID)
        var row: [String: Any] = [
            "schema_version": manifest.schemaVersion, "observation_id": observationID.uuidString.lowercased(),
            "analysis_id": analysisID.uuidString.lowercased(), "source_analysis_id": sourceAnalysisID.uuidString.lowercased(),
            "entitlement_protocol": 3, "identification_protocol": 7, "history_protocol": 10,
            "expected_processor_permission": "google_gemini",
            "evidence_manifest": try JSONSerialization.jsonObject(with: manifest.originalBytes)
        ]
        row["request_digest"] = try Self.digest(row)
        try self.init(savedBody: Self.canonical(row))
    }

    init(savedBody: Data) throws {
        guard !savedBody.isEmpty, savedBody.count <= 1_044_480 else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: savedBody), keys: [
            "schema_version", "observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest",
            "entitlement_protocol", "identification_protocol", "history_protocol", "expected_processor_permission"
        ])
        let version = try ObservationHistoryPage.integer(row["schema_version"])
        guard version == 5 || version == 6,
              try ObservationHistoryPage.integer(row["entitlement_protocol"]) == 3,
              try ObservationHistoryPage.integer(row["identification_protocol"]) == 7,
              try ObservationHistoryPage.integer(row["history_protocol"]) == 10,
              row["expected_processor_permission"] as? String == "google_gemini" else { throw MerianError.invalidResponse }
        let observation = try ObservationHistoryPage.uuid(row["observation_id"])
        let analysis = try ObservationHistoryPage.uuid(row["analysis_id"])
        let source = try ObservationHistoryPage.uuid(row["source_analysis_id"])
        let manifestRow = try ObservationHistoryPage.object(row["evidence_manifest"], keys: ["schema_version", "items"])
        let manifest = try ObservationCompositionManifest(data: Self.canonical(manifestRow), observationID: observation,
            analysisID: analysis, sourceAnalysisID: source)
        guard manifest.schemaVersion == version else { throw MerianError.invalidResponse }
        var unsigned = row
        unsigned.removeValue(forKey: "request_digest")
        guard let digest = row["request_digest"] as? String, digest == (try Self.digest(unsigned)) else { throw MerianError.invalidResponse }
        self.observationID = observation; self.analysisID = analysis; self.sourceAnalysisID = source
        self.manifest = manifest; self.body = savedBody; self.requestDigest = digest
    }

    private static func canonical(_ row: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private static func digest(_ row: [String: Any]) throws -> String {
        let bytes: Data
        if try ObservationHistoryPage.integer(row["schema_version"]) == 6 {
            let observation = try ObservationHistoryPage.uuid(row["observation_id"])
            let analysis = try ObservationHistoryPage.uuid(row["analysis_id"])
            let source = try ObservationHistoryPage.uuid(row["source_analysis_id"])
            let manifestRow = try ObservationHistoryPage.object(row["evidence_manifest"], keys: ["schema_version", "items"])
            let manifest = try ObservationCompositionManifest(data: canonical(manifestRow), observationID: observation,
                analysisID: analysis, sourceAnalysisID: source)
            bytes = try canonicalCompositionBytes(observationID: observation, analysisID: analysis,
                sourceAnalysisID: source, requestDigest: nil, manifest: manifest)
        } else { bytes = try canonical(row) }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
