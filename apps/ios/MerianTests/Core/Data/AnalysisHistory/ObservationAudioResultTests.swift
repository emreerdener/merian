import Foundation
@testable import Merian
import Testing

@MainActor
struct ObservationAudioResultTests {
    func fixture() throws -> (ObservationAudioReanalysisRequest, [String: Any]) {
        let (photo, _) = try ObservationReanalysisResultTests().fixture()
        var snapshot = try ObservationHistorySyncTests().audioSnapshot()
        let audio = try ObservationHistoryAudioReference.decodeManifest(snapshot["evidence_manifest"],
            observationID: photo.observationID, analysisID: photo.analysisID)
        let request = try ObservationAudioReanalysisRequest(observationID: photo.observationID, analysisID: photo.analysisID,
            sourceAnalysisID: photo.sourceAnalysisID, evidence: [.description("Before é"), .audio(audio), .description("After e\u{301}")])
        snapshot["analysis_id"] = request.analysisID.uuidString.lowercased()
        snapshot["observation_id"] = request.observationID.uuidString.lowercased()
        snapshot["source_analysis_id"] = request.sourceAnalysisID.uuidString.lowercased()
        snapshot["request_digest"] = request.requestDigest
        snapshot["evidence_manifest"] = ObservationAudioReanalysisRequest.manifest(request.evidence)
        return (request, snapshot)
    }

    @Test func exactV4ResultPreservesOriginalBytes() throws {
        let (request, snapshot) = try fixture()
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        let result = try ObservationReanalysisResult.decode(data, matching: request)
        #expect(result.version == 4 && result.bytes == data && result.analysisID == request.analysisID)
        #expect(result.audio != nil && result.photos.isEmpty)
        let (photo, _) = try ObservationReanalysisResultTests().fixture()
        #expect(throws: (any Error).self) { try ObservationReanalysisResult.decode(data, matching: photo) }
    }

    @Test(arguments: ["source", "child", "parent", "digest", "version", "order", "description", "length", "media", "sha"])
    func alteredAuthorityOrManifestCannotAppend(field: String) throws {
        let (request, original) = try fixture(); var snapshot = original
        switch field {
        case "source": snapshot["source_analysis_id"] = UUID().uuidString.lowercased()
        case "child": snapshot["analysis_id"] = UUID().uuidString.lowercased()
        case "parent": snapshot["observation_id"] = UUID().uuidString.lowercased()
        case "digest": snapshot["request_digest"] = String(repeating: "a", count: 64)
        case "version": snapshot["schema_version"] = 2
        default:
            var manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
            var items = try #require(manifest["items"] as? [[String: Any]])
            switch field {
            case "order": items.reverse()
            case "description": items[0]["text"] = "Changed"
            case "length": items[1]["byte_count"] = 48
            case "media": items[1]["media_id"] = UUID().uuidString.lowercased()
            default: items[1]["sha256"] = String(repeating: "c", count: 64)
            }
            manifest["items"] = items; snapshot["evidence_manifest"] = manifest
        }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisResult.decode(JSONSerialization.data(withJSONObject: snapshot), matching: request)
        }
    }
}
