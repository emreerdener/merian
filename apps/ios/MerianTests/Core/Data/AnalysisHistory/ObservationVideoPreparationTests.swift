import Foundation
@testable import Merian
import Testing

@Suite("Closed video preparation envelope")
struct ObservationVideoPreparationTests {
    private let digest = String(repeating: "a", count: 64)
    private func requests() throws -> [ObservationVideoReanalysisRequest] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/video-request-v4.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        return try fixtures.map { fixture in
            let row = try #require(fixture["input"])
            return try .init(savedBody: JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
        }
    }
    private func changed(_ data: Data, _ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var row = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try edit(&row)
        return try JSONSerialization.data(withJSONObject: row)
    }

    @Test func exactRequestReplayAndOrderedInventory() throws {
        for request in try requests() {
            let preparation = try ObservationVideoPreparation(ownerID: UUID(), request: request, sourceSnapshotSHA256: digest)
            let graph = request.manifest.provenance
            let artifacts = [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
            #expect(preparation.files.map(\.artifact) == artifacts)
            #expect(Set(preparation.files.map(\.path)).count == artifacts.count)
            #expect(preparation.files.first?.path.hasSuffix(".mp4") == true)
            for phase in [ObservationVideoPreparation.Phase.pending, .ready] {
                let restored = try ObservationVideoPreparation.decode(preparation.storedData(phase: phase))
                #expect(restored.preparation == preparation)
                #expect(restored.preparation.request.body == request.body)
                #expect(restored.phase == phase)
            }
        }
    }

    @Test func closedEnvelopeRejectsUnknownMissingAndWrongFields() throws {
        let preparation = try ObservationVideoPreparation(ownerID: UUID(), request: #require(requests().first), sourceSnapshotSHA256: digest)
        let data = try preparation.storedData(phase: .pending)
        let changes: [String: Any] = ["version": true, "kind": "audio_preparation", "phase": "admission_pending",
                                     "owner_id": "bad", "source_snapshot_sha256": String(repeating: "A", count: 64),
                                     "request_body": "{}", "files": [], "requested_action": "submit"]
        for (key, value) in changes {
            #expect(throws: (any Error).self) { try ObservationVideoPreparation.decode(changed(data) { $0[key] = value }) }
        }
        let row = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in row.keys {
            #expect(throws: (any Error).self) { try ObservationVideoPreparation.decode(changed(data) { $0.removeValue(forKey: key) }) }
        }
        for oversized in [Data(), Data(repeating: 32, count: ObservationVideoPreparation.maximumStoredBytes + 1)] {
            #expect(throws: (any Error).self) { try ObservationVideoPreparation.decode(oversized) }
        }
        #expect(throws: (any Error).self) { try ObservationAudioPreparation.decode(data) }
        #expect(throws: (any Error).self) { try ObservationReanalysisRequest(savedBody: data) }
        #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: data) }
    }

    @Test func inventoryRejectsTraversalSubstitutionOmissionAndReordering() throws {
        let preparation = try ObservationVideoPreparation(ownerID: UUID(), request: #require(requests().first), sourceSnapshotSHA256: digest)
        let data = try preparation.storedData(phase: .ready)
        for variant in 0..<7 {
            let invalid = try changed(data) { row in
                var files = try #require(row["files"] as? [[String: Any]])
                switch variant {
                case 0: files[0]["path"] = "../other.mp4"
                case 1: files[0]["path"] = "/tmp/caller.mp4"
                case 2: files[0]["media_id"] = UUID().uuidString.lowercased()
                case 3: files.removeLast()
                case 4: files.swapAt(0, 1)
                case 5: files[1] = files[0]
                default: files[0]["url"] = "forbidden"
                }
                row["files"] = files
            }
            #expect(throws: (any Error).self) { try ObservationVideoPreparation.decode(invalid) }
        }
    }

    @Test func ownerAliasesCannotQualifyInventory() throws {
        let request = try #require(requests().first)
        let graph = request.manifest.provenance
        let aliases = [request.observationID, request.analysisID, request.sourceAnalysisID, graph.source.mediaID]
            + graph.frames.map(\.artifact.mediaID) + (graph.audio.map { [$0.artifact.mediaID] } ?? [])
        for owner in aliases {
            #expect(throws: (any Error).self) { try ObservationVideoPreparation(ownerID: owner, request: request, sourceSnapshotSHA256: digest) }
        }
    }
}
