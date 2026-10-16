import Foundation
@testable import Merian
import Testing

@Suite("Prepared video reanalysis request")
struct ObservationVideoReanalysisRequestTests {
    private func fixtures() throws -> [[String: Any]] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/video-request-v4.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }
    private func identifier(_ row: [String: Any], _ key: String) throws -> UUID {
        let value = try #require(row[key] as? String)
        return try #require(UUID(uuidString: value))
    }
    private func fresh(_ row: [String: Any], source: UUID? = nil) throws -> ObservationVideoReanalysisRequest {
        let manifest = try #require(row["evidence_manifest"])
        let data = try JSONSerialization.data(withJSONObject: manifest)
        return try .init(observationID: identifier(row, "observation_id"), analysisID: identifier(row, "analysis_id"),
                         sourceAnalysisID: source ?? identifier(row, "source_analysis_id"), manifestBytes: data)
    }
    @Test func sharedGoldenDigestAndExactReplay() throws {
        let vectors = try fixtures()
        #expect(vectors.count == 2)
        for vector in vectors {
            let row = try #require(vector["input"] as? [String: Any])
            let canonical = try #require(vector["canonical_body"] as? String)
            let request = try fresh(row)
            #expect(request.body == Data(canonical.utf8))
            #expect(request.requestDigest == row["request_digest"] as? String)
            let pretty = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let restored = try ObservationVideoReanalysisRequest(savedBody: pretty)
            #expect(restored.body == pretty)
            #expect(restored.body != request.body)
            #expect(restored.manifest.provenance == request.manifest.provenance)
            #expect(restored.manifest.descriptions == request.manifest.descriptions)
            #expect(try ObservationVideoReanalysisRequest(savedBody: restored.body) == restored)
        }
    }
    @Test func allHistoricalSourceAliasesFailBeforeStaging() throws {
        let vector = try #require(fixtures().first)
        let row = try #require(vector["input"] as? [String: Any])
        let request = try fresh(row)
        let graph = request.manifest.provenance
        let ids = [request.observationID, request.analysisID, graph.source.mediaID] + graph.frames.map(\.artifact.mediaID) + (graph.audio.map { [$0.artifact.mediaID] } ?? [])
        for id in ids { #expect(throws: (any Error).self) { try fresh(row, source: id) } }
    }
    @Test func closedFieldsProtocolsAndDigest() throws {
        let vector = try #require(fixtures().first)
        let row = try #require(vector["input"] as? [String: Any])
        let changes: [String: Any] = ["schema_version": 3, "entitlement_protocol": true, "identification_protocol": 5,
                                     "history_protocol": 12, "expected_processor_permission": "openai", "request_digest": String(repeating: "b", count: 64),
                                     "source_analysis_id": NSNull(), "owner_id": "forbidden", "input_profile": "forbidden"]
        for (key, value) in changes {
            var changed = row; changed[key] = value
            let data = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: (any Error).self) { try ObservationVideoReanalysisRequest(savedBody: data) }
        }
        for key in row.keys {
            var missing = row; missing.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: missing)
            #expect(throws: (any Error).self) { try ObservationVideoReanalysisRequest(savedBody: data) }
        }
        let request = try fresh(row)
        #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: request.body) }
        #expect(throws: (any Error).self) { try ObservationReanalysisRequest(savedBody: request.body) }
        #expect(throws: (any Error).self) { try ObservationSourceFingerprint(input: request.body) }
        #expect(throws: (any Error).self) { try ObservationVideoReanalysisRequest(savedBody: Data(repeating: 32, count: 1_044_481)) }
    }
}
