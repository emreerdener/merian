import Foundation
@testable import Merian
import Testing

@Suite("Held video source fingerprint parity")
struct ObservationVideoSourceFingerprintTests {
    private func fixtures() throws -> [[String: Any]] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(
            at: "services/supabase/functions/_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }
    private func input(_ index: Int = 0) throws -> [String: Any] {
        try #require(fixtures()[index]["input"] as? [String: Any])
    }
    private func data(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func fingerprint(_ value: [String: Any]) throws -> ObservationVideoSourceFingerprint {
        try .init(input: data(value))
    }

    @Test func goldenAudioSilentAndUnicodeBytes() throws {
        let vectors = try fixtures()
        #expect(vectors.count == 3)
        for vector in vectors {
            let row = try #require(vector["input"] as? [String: Any])
            let result = try fingerprint(row)
            #expect(result.sha256 == vector["sha256"] as? String)
            #expect(result.canonicalBytes.map { String(format: "%02x", $0) }.joined() == vector["canonical_utf8_hex"] as? String)
            let pretty = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted])
            #expect(try ObservationVideoSourceFingerprint(input: pretty) == result)
            let json = try #require(String(data: data(row), encoding: .utf8))
            #expect(try ObservationVideoSourceFingerprint(input: Data(json.replacingOccurrences(of: ":100,", with: ":1e2,").utf8)) == result)
            #expect(throws: (any Error).self) { try ObservationSourceFingerprint(input: pretty) }
        }
    }

    @Test func everySemanticLeafChangesIdentityOrFailsClosed() throws {
        let row = try input(), baseline = try fingerprint(row)
        // Rebuild one branch for each leaf. This detects an omitted field without
        // mirroring the codec's field order or reconstructing expected bytes.
        func mutations(_ value: Any) -> [Any] {
            if let object = value as? [String: Any] {
                return object.keys.sorted().flatMap { key in
                    mutations(object[key]!).map { child in object.merging([key: child]) { _, new in new } as Any }
                }
            }
            if let array = value as? [Any] {
                return array.indices.flatMap { index in
                    mutations(array[index]).map { child in var copy = array; copy[index] = child; return copy as Any }
                }
            }
            if let number = value as? NSNumber {
                return [CFGetTypeID(number) == CFBooleanGetTypeID() ? false : number.intValue + 1]
            }
            if let string = value as? String { return [string + "x"] }
            return ["invalid"]
        }
        let changed = mutations(row)
        #expect(changed.count > 80)
        for candidate in changed {
            let changedRow = try #require(candidate as? [String: Any])
            if let result = try? fingerprint(changedRow) { #expect(result.canonicalBytes != baseline.canonicalBytes) }
        }
    }

    @Test func numericSpellingIsSemanticAndInvalidTextFails() throws {
        let row = try input()
        let json = try #require(String(data: data(row), encoding: .utf8))
            .replacingOccurrences(of: "\"start_ticks\":600", with: "\"start_ticks\":0")
            .replacingOccurrences(of: "\"end_ticks\":1800", with: "\"end_ticks\":1200")
        for (key, original) in [("crop_center_basis_points", "5000"), ("actual_time_ticks", "300"), ("start_ticks", "0")] {
            for zero in ["-0", "-0.0", "-0e0"] {
                let modified = json.replacingOccurrences(of: "\"\(key)\":\(original)", with: "\"\(key)\":\(zero)")
                #expect(modified != json)
                #expect(try ObservationVideoSourceFingerprint(input: Data(modified.utf8)) == ObservationVideoSourceFingerprint(input: Data(json.replacingOccurrences(of: "\"\(key)\":\(original)", with: "\"\(key)\":0").utf8)))
            }
        }
        var manifest = try #require(row["evidence_manifest"] as? [String: Any])
        manifest["descriptions"] = ["sentinel"]
        let text = try #require(String(data: data(row.merging(["evidence_manifest": manifest]) { _, new in new }), encoding: .utf8))
        for escape in ["\\ud800", "\\udc00", "\\u0000"] {
            #expect(throws: (any Error).self) { try ObservationVideoSourceFingerprint(input: Data(text.replacingOccurrences(of: "sentinel", with: escape).utf8)) }
        }
        // Frame indices are rebuilt by the prepared validator; this matches TS.
        #expect(try ObservationVideoSourceFingerprint(input: Data(json.replacingOccurrences(of: "\"index\":0", with: "\"index\":-0").utf8)) == ObservationVideoSourceFingerprint(input: Data(json.utf8)))
    }

    @Test func aliasesUnknownKeysAndOldSchemasFailClosed() throws {
        let row = try input()
        for patch: [String: Any] in [["schema_version": 3], ["schema_version": true], ["extra": 1],
            ["source_analysis_id": row["observation_id"]!], ["source_analysis_id": "00000000-0000-4000-8000-000000000003"],
            ["request_digest": "bad"], ["expected_processor_permission": "openai"]] {
            #expect(throws: (any Error).self) { try fingerprint(row.merging(patch) { _, new in new }) }
        }
        #expect(throws: (any Error).self) { try ObservationVideoSourceFingerprint(input: Data(repeating: 0x20, count: 1_044_481)) }
        #expect(throws: (any Error).self) { try ObservationVideoSourceFingerprint(input: Data()) }
    }

    @Test func descriptionOrderAndNormalizationRemainSignificant() throws {
        let row = try input()
        var manifest = try #require(row["evidence_manifest"] as? [String: Any])
        func encode(_ texts: [String]) throws -> ObservationVideoSourceFingerprint {
            manifest["descriptions"] = texts
            return try fingerprint(row.merging(["evidence_manifest": manifest]) { _, new in new })
        }
        #expect(try encode(["first", "second"]) != encode(["second", "first"]))
        #expect(try encode(["é"]) != encode(["e\u{0301}"]))
        _ = try encode(Array(repeating: String(repeating: "x", count: 8000), count: 4))
        for texts in [[""], [" \t\n"], [String(repeating: "x", count: 8193)], Array(repeating: "x", count: 65),
                      Array(repeating: String(repeating: "x", count: 8000), count: 4) + ["x"]] {
            #expect(throws: (any Error).self) { try encode(texts) }
        }
    }
}
