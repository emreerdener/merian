import Foundation
@testable import Merian
import Testing

struct ObservationReanalysisResultTests {
    func fixture() throws -> (ObservationReanalysisRequest, [String: Any]) {
        let file = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v2.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(file.utf8)) as? [String: Any])
        let text = try #require((page["items"] as? [[String: Any]])?.first?["snapshot"] as? String)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let request = try ObservationReanalysisRequest(
            observationID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            analysisID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
            sourceAnalysisID: UUID(uuidString: "00000000-0000-4000-8000-000000000006")!, processor: .gemini,
            evidence: [.image(.init(mediaID: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!,
                contentType: "image/jpeg", byteCount: 3,
                sha256: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")),
                .description("Synthetic private evidence.")])
        let input = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        snapshot["request_digest"] = input["request_digest"]
        snapshot["source_analysis_id"] = request.sourceAnalysisID.uuidString.lowercased()
        return (request, snapshot)
    }

    @Test func exactResultKeepsOriginalSnapshotBytes() throws {
        let (request, snapshot) = try fixture()
        let bytes = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        let result = try ObservationReanalysisResult.decode(bytes, matching: request)
        #expect(result.bytes == bytes && result.analysisID == request.analysisID)
        #expect(result.version == 2 && result.photos.count == 1)
    }

    @Test(arguments: ["source", "source-null", "digest", "child", "parent", "ordinal", "version", "provider"])
    func wrongProvenanceAndInvalidResultsFailClosed(field: String) throws {
        let (request, original) = try fixture(); var snapshot = original
        switch field {
        case "source": snapshot["source_analysis_id"] = UUID().uuidString.lowercased()
        case "source-null": snapshot["source_analysis_id"] = NSNull()
        case "digest": snapshot["request_digest"] = String(repeating: "a", count: 64)
        case "child": snapshot["analysis_id"] = UUID().uuidString.lowercased()
        case "parent": snapshot["observation_id"] = UUID().uuidString.lowercased()
        case "ordinal": snapshot["ordinal"] = 0
        case "version": snapshot["schema_version"] = 1
        default:
            var result = try #require(snapshot["result"] as? [String: Any])
            result["ai_reasoning"] = ""; snapshot["result"] = result
        }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisResult.decode(JSONSerialization.data(withJSONObject: snapshot), matching: request)
        }
    }

    @Test(arguments: ["order", "description", "digest", "length", "media", "type", "extra"])
    func fullManifestMustMatchEvenWhenPhotosAloneLookValid(field: String) throws {
        let (request, original) = try fixture(); var snapshot = original
        var manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
        var items = try #require(manifest["items"] as? [[String: Any]])
        switch field {
        case "order": items.reverse()
        case "description": items[1]["text"] = "A different private description."
        case "digest": items[0]["sha256"] = String(repeating: "b", count: 64)
        case "length": items[0]["byte_count"] = 4
        case "media": items[0]["media_id"] = UUID().uuidString.lowercased()
        case "type": items[0]["content_type"] = "image/png"
        default: items.append(["kind": "description", "text": "Unexpected extra evidence."])
        }
        manifest["items"] = items; snapshot["evidence_manifest"] = manifest
        #expect(throws: (any Error).self) {
            try ObservationReanalysisResult.decode(JSONSerialization.data(withJSONObject: snapshot), matching: request)
        }
    }
}
