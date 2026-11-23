import Foundation
@testable import Merian
import Testing

struct SharedMediaCaptureArtifactRequestTests {
    private func plan() throws -> CaptureInitialEvidencePlan {
        let raw = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        let fixture = try #require(fixtures.first { $0["name"] as? String == "video_audio" })
        return try .init(ownerID: ObservationHistoryPage.uuid(fixture["owner_id"]),
            data: JSONSerialization.data(withJSONObject: #require(fixture["plan"])))
    }
    private func request(_ plan: CaptureInitialEvidencePlan, mediaID: UUID, ownerID: UUID? = nil) throws -> SharedMediaCaptureArtifactRequest {
        let profile = SharedMediaNativeAppProfile(ownerID: ownerID ?? plan.ownerID, inventoryID: UUID(),
            generation: UUID(), storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
            receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
        return try plan.artifactRequest(mediaID: mediaID, id: UUID(), profile: profile, writerEpoch: UUID(),
            rootBindingSHA256: String(repeating: "c", count: 64), inventoryRevision: 0,
            allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
    }

    @Test func onlyExactLocalRolesBecomeRequests() throws {
        let plan = try plan()
        for upload in plan.uploads {
            let request = try request(plan, mediaID: upload.artifact.mediaID)
            #expect(request.itemIndex == upload.itemIndex && request.frameIndex == upload.frameIndex)
            #expect(request.planSHA256 == (try SharedMediaAcquisitionEncoding.digest(plan.encoded())))
            #expect(request.byteCount == upload.artifact.byteCount && request.sha256 == upload.artifact.sha256)
            #expect(try SharedMediaCaptureArtifactRequest.decode(request.encoded(), sha256: request.digest) == request)
        }
        for node in plan.items {
            let prepared: UUID?
            switch node {
            case .audio(let audio): prepared = audio.preparedMediaID
            case .video(let video): prepared = video.audio?.preparedMediaID
            default: prepared = nil
            }
            if let prepared { #expect(throws: (any Error).self) { try request(plan, mediaID: prepared) } }
        }
        let media = try #require(plan.uploads.first).artifact.mediaID
        #expect(throws: (any Error).self) { try request(plan, mediaID: media, ownerID: UUID()) }
    }

    @Test(arguments: ["role", "frame", "identityAlias", "negativeBytes", "oversizedBytes", "digest", "path", "trailing"])
    func tamperedRequestsNeverAuthorizeAReservation(_ mutation: String) throws {
        let plan = try plan(), media = try #require(plan.uploads.first).artifact.mediaID
        let request = try request(plan, mediaID: media)
        var object = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        switch mutation {
        case "role": object["role"] = "prepared_audio"
        case "frame": object["frameIndex"] = 0
        case "identityAlias": object["leaseID"] = object["allocationID"]
        case "negativeBytes": object["byteCount"] = -1
        case "oversizedBytes": object["byteCount"] = 100_000_000
        case "digest": object["planSHA256"] = "invalid"
        case "path": object["finalName"] = "../unowned"
        case "trailing": break
        default: Issue.record("Unknown mutation")
        }
        var bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if mutation == "trailing" { bytes.append(32) }
        #expect(throws: (any Error).self) {
            _ = try SharedMediaCaptureArtifactRequest.decode(bytes, sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        }
    }
}
