import Foundation
@testable import Merian
import Testing

struct ObservationInitialEvidenceTests {
    @Test func fullOriginalMatchesSharedV8DigestWithoutChangingPreparedLimit() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v8-originals.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let rows = try #require(page["items"] as? [[String: Any]])
        let snapshotText = try #require(rows.first?["snapshot"] as? String)
        let snapshot = try #require(JSONSerialization.jsonObject(with: Data(snapshotText.utf8)) as? [String: Any])
        let evidence = try #require(decode(snapshot).initialEvidence)
        #expect(evidence.manifestVersion == 8)
        guard case let .image(source, prepared, _) = evidence.items[0] else {
            Issue.record("Original image missing"); return
        }
        #expect(source.byteCount == 33_554_432)
        #expect(prepared.byteCount <= 5_242_880)
        let result = try decode(snapshot)
        let observation = try ObservationHistoryPage.uuid(snapshot["observation_id"])
        let context = try ObservationCompositionSource(ownerID: evidence.ownerID, observationID: observation, result: result)
        #expect(context.resolutionProtocol == 3)
        #expect(context.isRetainedOriginalImage(source))
        #expect(!context.isRetainedOriginalImage(prepared))
        let request = ObservationHistoryMediaRequest(observation_id: observation.uuidString.lowercased(),
            analysis_id: result.analysisID.uuidString.lowercased(), media_id: source.mediaID.uuidString.lowercased(), resolution_protocol: 3)
        let ticket = try JSONDecoder().decode(ObservationHistoryPhotoTicket.self, from: JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "owner_id": evidence.ownerID.uuidString.lowercased(),
            "observation_id": request.observation_id, "analysis_id": request.analysis_id, "media_id": request.media_id,
            "content_type": source.contentType, "byte_count": source.byteCount, "sha256": source.sha256,
            "url": "https://00000000000000000000000000000000.r2.cloudflarestorage.com/synthetic",
            "expires_at_ms": 31_000
        ]))
        try ticket.validateMedia(owner: evidence.ownerID, request: request, artifact: source,
            now: Date(timeIntervalSince1970: 1), source: context)
        #expect(throws: (any Error).self) {
            try ticket.validateMedia(owner: evidence.ownerID, request: request, artifact: source, now: Date(timeIntervalSince1970: 1))
        }
        var oldRequest = request; oldRequest.resolution_protocol = 2
        #expect(throws: (any Error).self) {
            try ticket.validateMedia(owner: evidence.ownerID, request: oldRequest, artifact: source,
                now: Date(timeIntervalSince1970: 1), source: context)
        }
        var changed = snapshot
        var manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
        manifest["schema_version"] = 7
        changed["evidence_manifest"] = manifest
        #expect(throws: (any Error).self) { try decode(changed) }
        let (_, old) = try fixture()
        #expect(try decode(old).initialEvidence?.manifestVersion == 7)
    }
    @Test func geometryManifestMatchesSharedDigestAndBindsItsOriginalPair() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v8-geometry.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let rows = try #require(page["items"] as? [[String: Any]])
        let snapshotText = try #require(rows.first?["snapshot"] as? String)
        let snapshot = try #require(JSONSerialization.jsonObject(with: Data(snapshotText.utf8)) as? [String: Any])
        let result = try decode(snapshot), evidence = try #require(result.initialEvidence)
        #expect(evidence.manifestVersion == 9)
        guard case let .image(original, prepared, _) = evidence.items[0] else {
            Issue.record("Original image missing"); return
        }
        let geometry = try #require(evidence.photoPreparations[prepared.mediaID])
        #expect(geometry.format == .selectedStillImage)
        #expect(geometry.cropDisplaySize == 390)
        #expect(evidence.photoPreparations[original.mediaID] == nil)
        let source = try ObservationCompositionSource(ownerID: evidence.ownerID,
            observationID: ObservationHistoryPage.uuid(snapshot["observation_id"]), result: result)
        #expect(source.resolutionProtocol == 3 && source.isRetainedOriginalImage(original))
        #expect(!source.isRetainedOriginalImage(prepared))
        // A V9 recipe alone does not grant raw-file ownership or UI reframing.
        #expect(!source.permitsPhotoReframing(prepared.mediaID))
        var altered = snapshot
        var manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
        var items = try #require(manifest["items"] as? [[String: Any]])
        var changedGeometry = geometry.object
        changedGeometry["offset_x"] = geometry.offsetX + 1
        items[0]["preparation"] = changedGeometry
        manifest["items"] = items; altered["evidence_manifest"] = manifest
        #expect(throws: (any Error).self) { try decode(altered) }
        items[0].removeValue(forKey: "preparation")
        manifest["items"] = items; altered["evidence_manifest"] = manifest
        #expect(throws: (any Error).self) { try decode(altered) }
        let (_, legacy) = try fixture()
        #expect(try decode(legacy).initialEvidence?.photoPreparations.isEmpty == true)
    }

    func fixture() throws -> (page: [String: Any], snapshot: [String: Any]) {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v8.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let items = try #require(page["items"] as? [[String: Any]])
        let snapshot = try #require(items.first?["snapshot"] as? String)
        return (page, try #require(JSONSerialization.jsonObject(with: Data(snapshot.utf8)) as? [String: Any]))
    }
    func decode(_ snapshot: [String: Any]) throws -> ObservationHistoryPage.Result {
        try ObservationHistoryPage.snapshot(JSONSerialization.data(withJSONObject: snapshot),
            observationID: try #require(snapshot["observation_id"] as? String), ordinal: 1)
    }
    @Test func originalEvidenceMatchesSharedDigestAndPreservesClipOwnership() throws {
        let (_, snapshot) = try fixture(), result = try decode(snapshot)
        let evidence = try #require(result.initialEvidence)
        #expect(result.version == 8)
        #expect(result.composition == nil)
        #expect(evidence.items.count == 3)
        guard case let .image(source, prepared, focus) = evidence.items[0],
              case let .description(text) = evidence.items[1],
              case let .video(clip) = evidence.items[2] else { Issue.record("Original evidence lost node order"); return }
        #expect(source.contentType == "image/heif")
        #expect(source.mediaID != prepared.mediaID)
        #expect(focus?.source == .userSelection)
        #expect(focus?.x == 0.1)
        #expect(text == "  Synthetic 🦋 context.  ")
        #expect(clip.frames.count == 2)
        #expect(clip.source.mediaID != clip.playback.mediaID)
        #expect(clip.audio?.source.contentType == "audio/mp4")
        #expect(clip.audio?.prepared.contentType == "audio/wav")
    }
    @Test func rejectsChangedManifestProofAndIdentityBeforeAdmission() throws {
        let (_, snapshot) = try fixture()
        var altered = snapshot
        var manifest = try #require(snapshot["evidence_manifest"] as? [String: Any])
        var items = try #require(manifest["items"] as? [[String: Any]])
        var focus = try #require(items[0]["focus_region"] as? [String: Any])
        focus["x"] = 0.11; items[0]["focus_region"] = focus
        manifest["items"] = items; altered["evidence_manifest"] = manifest
        #expect(throws: (any Error).self) { try decode(altered) }
        for key in ["owner_id", "generation", "scan_id"] {
            altered = snapshot
            var proof = try #require(snapshot["initial_evidence"] as? [String: Any])
            proof[key] = snapshot["analysis_id"]; altered["initial_evidence"] = proof
            #expect(throws: (any Error).self) { try decode(altered) }
        }
        altered = snapshot; altered["ordinal"] = 2
        #expect(throws: (any Error).self) { try decode(altered) }
        altered = snapshot; altered.removeValue(forKey: "initial_evidence")
        #expect(throws: (any Error).self) { try decode(altered) }
    }
    @Test func sourceAdapterPreservesPreparedCoordinatesAndDistinctVideoRoles() throws {
        let (_, snapshot) = try fixture(), result = try decode(snapshot)
        let evidence = try #require(result.initialEvidence)
        let observation = try ObservationHistoryPage.uuid(snapshot["observation_id"])
        let source = try ObservationCompositionSource(ownerID: evidence.ownerID, observationID: observation, result: result)
        #expect(source.resolutionProtocol == 2)
        #expect(source.artifacts == evidence.artifacts)
        #expect(source.nodes.count == 3)
        guard case let .image(photo) = source.nodes[0],
              case let .description(text) = source.nodes[1],
              case let .initialVideo(video) = source.nodes[2],
              case let .image(original, prepared, focus) = evidence.items[0] else {
            Issue.record("Initial source coerced ordinary roles into a reanalysis recipe"); return
        }
        #expect(photo == prepared && photo != original)
        #expect(source.imageFocusRegions[photo.mediaID] == focus)
        #expect(!source.permitsPhotoReframing(photo.mediaID))
        #expect(text == "  Synthetic 🦋 context.  ")
        #expect(video.frames.count == 2 && video.source.mediaID != video.playback.mediaID)
        #expect(throws: (any Error).self) {
            try ObservationCompositionSource(ownerID: UUID(), observationID: observation, result: result)
        }
    }
    @Test func pageRejectsAnOtherwiseValidProofFromAnotherOwner() throws {
        let (page, snapshot) = try fixture()
        var changed = snapshot, proof = try #require(snapshot["initial_evidence"] as? [String: Any])
        proof["owner_id"] = "00000000-0000-4000-8000-000000000099"
        changed["initial_evidence"] = proof
        var changedPage = page
        changedPage["items"] = [["ordinal": 1, "snapshot": String(decoding: try JSONSerialization.data(withJSONObject: changed), as: UTF8.self)]]
        let owner = try ObservationHistoryPage.uuid(page["owner_id"])
        let request = ObservationHistoryPageRequest(observation_id: try #require(page["observation_id"] as? String), before_ordinal: nil, limit: 20)
        #expect(throws: (any Error).self) {
            try ObservationHistoryPage.decode(JSONSerialization.data(withJSONObject: changedPage), request: request, ownerID: owner)
        }
    }
}
