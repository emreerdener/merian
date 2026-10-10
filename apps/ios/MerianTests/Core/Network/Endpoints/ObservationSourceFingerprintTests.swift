import Foundation
@testable import Merian
import Testing

@Suite("Source reservation fingerprint parity")
struct ObservationSourceFingerprintTests {
    private func fixtures() throws -> [[String: Any]] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(
            at: "services/supabase/functions/_shared/analysisHistory/fixtures/source-fingerprint-v1.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    private func encode(_ row: [String: Any]) throws -> ObservationSourceFingerprint {
        try .init(input: JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
    }

    @Test func sharedGoldenBytesAndHashesForBothPhotoProvidersAndAudio() throws {
        let vectors = try fixtures()
        #expect(vectors.count == 3)
        for vector in vectors {
            let row = try #require(vector["input"] as? [String: Any])
            let result = try encode(row)
            #expect(result.sha256 == vector["sha256"] as? String)
            #expect(result.canonicalBytes.map { String(format: "%02x", $0) }.joined() == vector["canonical_utf8_hex"] as? String)
            let pretty = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .withoutEscapingSlashes])
            #expect(try ObservationSourceFingerprint(input: pretty) == result)
            let integerJSON = try #require(String(data: pretty, encoding: .utf8))
            let decimalJSON = integerJSON.replacingOccurrences(of: ": 46,", with: ": 46.0,")
            #expect(decimalJSON != integerJSON)
            #expect(try ObservationSourceFingerprint(input: Data(decimalJSON.utf8)) == result)
        }
    }

    private func withDescriptions(_ texts: [String]) throws -> [String: Any] {
        var row = try #require(fixtures()[1]["input"] as? [String: Any])
        var manifest = try #require(row["evidence_manifest"] as? [String: Any])
        let items = try #require(manifest["items"] as? [[String: Any]])
        manifest["items"] = items.filter { $0["kind"] as? String == "audio" } + texts.map { ["kind": "description", "text": $0] }
        row["evidence_manifest"] = manifest
        return row
    }

    @Test func exactECMAScriptWhitespaceAndUnicodeBounds() throws {
        for text in ["\u{0085}", "\u{200B}", "\u{180E}", "x\u{FEFF}", "é", "e\u{0301}", "🦋", String(repeating: "x", count: 8192)] {
            _ = try encode(withDescriptions([text]))
        }
        for text in ["", " \t\n", "\u{FEFF}", "\u{2028}\u{2029}", "x\0y", String(repeating: "x", count: 8193)] {
            #expect(throws: (any Error).self) { try encode(withDescriptions([text])) }
        }
        let composed = try encode(withDescriptions(["é"]))
        let decomposed = try encode(withDescriptions(["e\u{0301}"]))
        #expect(composed.canonicalBytes != decomposed.canonicalBytes)
        _ = try encode(withDescriptions(Array(repeating: String(repeating: "x", count: 8000), count: 4)))
        #expect(throws: (any Error).self) { try encode(withDescriptions(Array(repeating: String(repeating: "x", count: 8000), count: 4) + ["x"])) }
        #expect(throws: (any Error).self) { try encode(withDescriptions(Array(repeating: "x", count: 64))) }
    }

    @Test func whitespaceHasExactFixedBytesAndHash() throws {
        let cases = [("\u{0085}", "63b77155fe436ccf04370d0ec80c8254409cd5b71e0f0e6403114ccbb2b82af2"),
                     ("x\u{FEFF}", "825b86fa8308aa65deb62352595d69d4a0cb95c9ebc4a038beb8a8868d88a959")]
        for (text, hash) in cases {
            let result = try encode(withDescriptions([text]))
            #expect(result.sha256 == hash)
            let suffix = Data("11:description,\(text.utf8.count):\(text),".utf8)
            #expect(result.canonicalBytes.suffix(suffix.count) == suffix)
        }
    }

    @Test func photoAliasesCountsAndAggregateLimits() throws {
        var row = try #require(fixtures()[0]["input"] as? [String: Any])
        var manifest = try #require(row["evidence_manifest"] as? [String: Any])
        let items = try #require(manifest["items"] as? [[String: Any]])
        let image = try #require(items.first { $0["kind"] as? String == "image" })
        for patch: [String: Any] in [["byte_count": 0], ["byte_count": 5_242_881],
            ["media_id": row["source_analysis_id"]!], ["content_type": "audio/wav"]] {
            manifest["items"] = [image.merging(patch) { _, new in new }]
            row["evidence_manifest"] = manifest
            #expect(throws: (any Error).self) { try encode(row) }
        }
        let images = (4...9).map { index in
            image.merging(["media_id": String(format: "00000000-0000-4000-8000-%012d", index), "byte_count": 1]) { _, new in new }
        }
        manifest["items"] = Array(images.prefix(5))
        row["evidence_manifest"] = manifest
        _ = try encode(row)
        for invalid in [images, [image, image],
            [image.merging(["byte_count": 5_242_880]) { _, new in new }, images[1]]] {
            manifest["items"] = invalid
            row["evidence_manifest"] = manifest
            #expect(throws: (any Error).self) { try encode(row) }
        }
        manifest["items"] = [image.merging(["byte_count": 5_242_880]) { _, new in new }]
        row["evidence_manifest"] = manifest
        _ = try encode(row)
    }

    @Test func malformedMetadataAndSurrogatesFailClosed() throws {
        let row = try #require(fixtures()[1]["input"] as? [String: Any])
        for patch: [String: Any] in [["schema_version": true], ["schema_version": 4], ["source_analysis_id": NSNull()],
            ["source_analysis_id": row["analysis_id"]!], ["extra": 1], ["request_digest": "bad"],
            ["history_protocol": 8], ["expected_processor_permission": "openai"]] {
            #expect(throws: (any Error).self) { try encode(row.merging(patch) { _, new in new }) }
        }
        let data = try JSONSerialization.data(withJSONObject: withDescriptions(["sentinel"]))
        let json = try #require(String(data: data, encoding: .utf8))
        for escape in ["\\ud800", "\\udc00", "\\u0000"] {
            #expect(throws: (any Error).self) {
                try ObservationSourceFingerprint(input: Data(json.replacingOccurrences(of: "sentinel", with: escape).utf8))
            }
        }
    }

    @Test func mediaIdentityAndByteLimits() throws {
        var row = try #require(fixtures()[1]["input"] as? [String: Any])
        var manifest = try #require(row["evidence_manifest"] as? [String: Any])
        let items = try #require(manifest["items"] as? [[String: Any]])
        let media = try #require(items.first { $0["kind"] as? String == "audio" })
        for patch: [String: Any] in [["byte_count": 0], ["byte_count": 45], ["byte_count": 46.5], ["byte_count": true],
            ["byte_count": "46"], ["byte_count": 2_700_001], ["media_id": row["source_analysis_id"]!]] {
            manifest["items"] = [media.merging(patch) { _, new in new }]
            row["evidence_manifest"] = manifest
            #expect(throws: (any Error).self) { try encode(row) }
        }
        manifest["items"] = [media.merging(["byte_count": 2_700_000]) { _, new in new }]
        row["evidence_manifest"] = manifest
        _ = try encode(row)
    }
}
