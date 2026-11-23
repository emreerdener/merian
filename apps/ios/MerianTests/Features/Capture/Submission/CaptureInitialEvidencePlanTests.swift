import Foundation
@testable import Merian
import Testing

struct CaptureInitialEvidencePlanTests {
    private func fixtures() throws -> [[String: Any]] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    @Test func sharedPlansPreserveOrderGeometryAndOnlyLocalUploadLiabilities() throws {
        let counts = ["two_photos": 4, "two_audio": 2, "photo_audio": 3, "video_audio": 6]
        for fixture in try fixtures() {
            let owner = try ObservationHistoryPage.uuid(fixture["owner_id"])
            let raw = try #require(fixture["plan"] as? [String: Any])
            let bytes = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
            let plan = try CaptureInitialEvidencePlan(ownerID: owner, data: bytes)
            #expect(try plan.encoded() == bytes)
            #expect(try CaptureInitialEvidencePlan(ownerID: owner, data: plan.encoded()) == plan)
            let name = try #require(fixture["name"] as? String)
            #expect(plan.uploads.count == counts[name])
            #expect(plan.uploads.map(\.itemIndex).allSatisfy { $0 != 1 })
            guard case let .description(note) = plan.items[1] else { Issue.record("Lost interleaved Field Notes"); continue }
            #expect(note == "  Synthetic 🦋 field note.  ")
            for node in plan.items {
                let preparedAudio: UUID?
                switch node {
                case let .audio(audio): preparedAudio = audio.preparedMediaID
                case let .video(video): preparedAudio = video.audio?.preparedMediaID
                default: preparedAudio = nil
                }
                if let preparedAudio { #expect(!plan.uploads.contains { $0.artifact.mediaID == preparedAudio }) }
            }
        }
    }

    @Test func automaticFocusRemainsDistinctFromManualSelection() throws {
        let fixture = try #require(fixtures().first { $0["name"] as? String == "two_photos" })
        let owner = try ObservationHistoryPage.uuid(fixture["owner_id"])
        var raw = try #require(fixture["plan"] as? [String: Any])
        var items = try #require(raw["items"] as? [[String: Any]])
        var focus = try #require(items[0]["focus_region"] as? [String: Any])
        focus["source"] = "vision_objectness"; items[0]["focus_region"] = focus; raw["items"] = items
        let bytes = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        let plan = try CaptureInitialEvidencePlan(ownerID: owner, data: bytes)
        #expect(try plan.encoded() == bytes)
        guard case let .image(_, _, actual, _) = plan.items[0] else { Issue.record("Expected photo"); return }
        #expect(actual?.source == .visionObjectness)
    }

    @Test func rejectsForgedAudioOutputOwnerCollisionsAndUnknownFields() throws {
        let fixture = try #require(fixtures().first { $0["name"] as? String == "two_audio" })
        let owner = try ObservationHistoryPage.uuid(fixture["owner_id"])
        let raw = try #require(fixture["plan"] as? [String: Any])
        var items = try #require(raw["items"] as? [[String: Any]])
        var forged = raw
        items[0]["prepared"] = ["sha256": String(repeating: "0", count: 64)]
        forged["items"] = items
        #expect(throws: (any Error).self) { try CaptureInitialEvidencePlan(ownerID: owner, data: JSONSerialization.data(withJSONObject: forged)) }
        forged = raw; forged["owner_id"] = owner.uuidString.lowercased()
        #expect(throws: (any Error).self) { try CaptureInitialEvidencePlan(ownerID: owner, data: JSONSerialization.data(withJSONObject: forged)) }
        let scan = try ObservationHistoryPage.uuid(raw["scan_id"])
        #expect(throws: (any Error).self) { try CaptureInitialEvidencePlan(ownerID: scan, data: JSONSerialization.data(withJSONObject: raw)) }
    }
}
