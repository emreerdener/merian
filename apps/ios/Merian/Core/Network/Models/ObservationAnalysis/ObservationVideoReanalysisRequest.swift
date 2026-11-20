import CryptoKit
import Foundation

/// Prepared schema-4 input; dispatch requires the separate durable video execution permit.
struct ObservationVideoReanalysisRequest: Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    let sourceAnalysisID: UUID
    let manifest: ObservationVideoManifest
    let body: Data
    let requestDigest: String

    init(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID, manifestBytes: Data) throws {
        let manifest = try ObservationVideoManifest(data: manifestBytes, observationID: observationID, analysisID: analysisID)
        var row: [String: Any] = [
            "schema_version": 4, "observation_id": observationID.uuidString.lowercased(),
            "analysis_id": analysisID.uuidString.lowercased(), "source_analysis_id": sourceAnalysisID.uuidString.lowercased(),
            "entitlement_protocol": 3, "identification_protocol": 6, "history_protocol": 9,
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
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 4,
              try ObservationHistoryPage.integer(row["entitlement_protocol"]) == 3,
              try ObservationHistoryPage.integer(row["identification_protocol"]) == 6,
              try ObservationHistoryPage.integer(row["history_protocol"]) == 9,
              row["expected_processor_permission"] as? String == "google_gemini" else { throw MerianError.invalidResponse }
        let observation = try ObservationHistoryPage.uuid(row["observation_id"])
        let analysis = try ObservationHistoryPage.uuid(row["analysis_id"])
        let source = try ObservationHistoryPage.uuid(row["source_analysis_id"])
        guard Set([observation, analysis, source]).count == 3 else { throw MerianError.invalidResponse }
        let manifestRow = try ObservationHistoryPage.object(row["evidence_manifest"], keys: ["schema_version", "provenance", "descriptions"])
        let manifest = try ObservationVideoManifest(data: Self.canonical(manifestRow), observationID: observation, analysisID: analysis)
        let graph = manifest.provenance
        let ids = [graph.source.mediaID] + graph.frames.map(\.artifact.mediaID) + (graph.audio.map { [$0.artifact.mediaID] } ?? [])
        guard !ids.contains(source) else { throw MerianError.invalidResponse }
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
        SHA256.hash(data: try canonical(row)).map { String(format: "%02x", $0) }.joined()
    }
}
