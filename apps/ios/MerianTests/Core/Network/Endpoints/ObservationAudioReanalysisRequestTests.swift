import CryptoKit
import Foundation
@testable import Merian
import Testing

@Suite("Immutable audio reanalysis request")
struct ObservationAudioReanalysisRequestTests {
    private let observation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private let source = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    private let media = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!

    private var audio: ObservationHistoryAudioReference {
        .init(mediaID: media, contentType: "audio/wav", byteCount: 46, sha256: String(repeating: "a", count: 64))
    }
    private func request(_ evidence: [ObservationAudioReanalysisRequest.Evidence]) throws -> ObservationAudioReanalysisRequest {
        try .init(observationID: observation, analysisID: analysis, sourceAnalysisID: source, evidence: evidence)
    }

    @Test func exactSavedBytesAndOrderedEvidenceSurviveReopening() throws {
        let evidence: [ObservationAudioReanalysisRequest.Evidence] = [.description("  before / 🌱  "), .audio(audio), .description("after")]
        let original = try request(evidence)
        let restored = try ObservationAudioReanalysisRequest(savedBody: original.body)
        #expect(restored == original)
        #expect(restored.evidence == evidence)
        #expect(original.requestDigest == "dfb5618dc14705a9a9ea209822bc2c961d61b4ad979e4f14b72a7f5407ec371e")
        let row = try #require(JSONSerialization.jsonObject(with: original.body) as? [String: Any])
        #expect(row["history_protocol"] as? Int == 9)
        #expect(row["expected_processor_permission"] as? String == "google_gemini")
        let spaced = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        #expect(try ObservationAudioReanalysisRequest(savedBody: spaced).body == spaced)
        #expect(throws: (any Error).self) { try ObservationReanalysisRequest(savedBody: original.body) }
    }

    @Test func rejectsUnsupportedVersionsProvidersIdentitiesAndDigest() throws {
        let original = try request([.audio(audio)])
        let row = try #require(JSONSerialization.jsonObject(with: original.body) as? [String: Any])
        for patch: [String: Any] in [["schema_version": 2], ["schema_version": true], ["history_protocol": 10],
            ["entitlement_protocol": 2], ["identification_protocol": 5], ["expected_processor_permission": "openai"],
            ["expected_processor_permission": "recovery_only"], ["source_analysis_id": analysis.uuidString.lowercased()],
            ["source_analysis_id": media.uuidString.lowercased()], ["observation_id": "ABCDEF00-0000-4000-8000-000000000002"],
            ["url": "forbidden"]] {
            // Rehash so the field contract, not an incidental digest mismatch, rejects it.
            let changed = try encodeRehashed(row.merging(patch) { _, new in new })
            #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: changed) }
        }
        var changed = row
        changed["request_digest"] = String(repeating: "b", count: 64)
        #expect(throws: (any Error).self) {
            try ObservationAudioReanalysisRequest(savedBody: JSONSerialization.data(withJSONObject: changed))
        }
    }

    @Test func enforcesAudioCountAndExactUnicodeLimits() throws {
        for evidence: [ObservationAudioReanalysisRequest.Evidence] in [[], [.description("only")], [.audio(audio), .audio(audio)],
            [.audio(audio), .description("\u{FEFF}")], [.audio(audio), .description(String(repeating: "a", count: 8193))],
            Array(repeating: .description("a"), count: 64) + [.audio(audio)],
            [.audio(audio), .description(String(repeating: "🌱", count: 8192)), .description(String(repeating: "🌱", count: 8192))]] {
            #expect(throws: (any Error).self) { try request(evidence) }
        }
        #expect(try request([.audio(audio), .description("\u{0085}")]).evidence.count == 2)
        #expect(try request([.audio(audio), .description(String(repeating: "🌱", count: 8192))]).evidence.count == 2)
        let photo = try ObservationReanalysisRequest(observationID: observation, analysisID: analysis, sourceAnalysisID: source,
            processor: .gemini, evidence: [.image(.init(mediaID: media, contentType: "image/png", byteCount: 46, sha256: audio.sha256))])
        #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: photo.body) }
        #expect(try ObservationReanalysisRequest(savedBody: photo.body) == photo)
    }

    private func encodeRehashed(_ row: [String: Any]) throws -> Data {
        var row = row
        row.removeValue(forKey: "request_digest")
        let unsigned = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        row["request_digest"] = SHA256.hash(data: unsigned).map { String(format: "%02x", $0) }.joined()
        return try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
