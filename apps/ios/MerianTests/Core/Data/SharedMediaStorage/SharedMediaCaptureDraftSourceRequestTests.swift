import Foundation
@testable import Merian
import Testing

struct CaptureDraftSourceRequestTests {
    func request(role: SharedMediaCaptureArtifactRequest.Role = .sourceImage,
                 origin: SharedMediaCaptureDraftSourceContext.Origin = .camera) throws -> SharedMediaCaptureArtifactRequest {
        let profile = SharedMediaNativeAppProfile(ownerID: UUID(), inventoryID: UUID(), generation: UUID(),
            storeIdentity: UUID().uuidString, physicalBinding: String(repeating: "a", count: 64),
            receiptDigest: String(repeating: "b", count: 64), physicalBindingFormat: .physicalRootsV1)
        let type: String
        switch role {
        case .sourceAudio, .sourceCompanionAudio: type = "audio/wav"
        case .sourceVideo: type = "video/mp4"
        default: type = "image/jpeg"
        }
        let input = SharedMediaCaptureDraftSourceInput(id: UUID(), scanID: UUID(), submissionGeneration: UUID(),
            mediaID: UUID(), itemIndex: 2, role: role, contentType: type, byteCount: 128,
            sha256: String(repeating: "c", count: 64),
            context: .init(origin: origin, cameraVerticalCenter: origin == .camera ? 0.4 : nil))
        return try .init(source: input, profile: profile, writerEpoch: UUID(),
            rootBindingSHA256: String(repeating: "d", count: 64), inventoryRevision: 0,
            allocationID: UUID(), referenceID: UUID(), leaseID: UUID())
    }

    @Test func sourceFormatRetainsFramingWithoutInventingAFinalPlan() throws {
        let value = try request()
        #expect(value.format == .draftSourceV1 && value.planSHA256 == nil && value.schemaVersion == 2)
        #expect(value.draftSource?.cameraVerticalCenter == 0.4)
        let data = try value.encoded()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["planSHA256"] == nil)
        #expect(try SharedMediaCaptureArtifactRequest.decode(data, sha256: value.digest) == value)
    }

    @Test(arguments: ["plan", "format", "derived", "frame", "context", "origin", "center", "unknown"])
    func rejectsAmbiguousOrForgedDraftSourceFacts(_ mutation: String) throws {
        let value = try request()
        var object = try #require(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        var context = try #require(object["draftSource"] as? [String: Any])
        switch mutation {
        case "plan": object["planSHA256"] = String(repeating: "e", count: 64)
        case "format": object["format"] = "captureArtifactRequestV1"
        case "derived": object["role"] = "prepared_image"
        case "frame": object["frameIndex"] = 0
        case "context": object.removeValue(forKey: "draftSource")
        case "origin": context["origin"] = "microphone"; object["draftSource"] = context
        case "center": context["cameraVerticalCenter"] = 2; object["draftSource"] = context
        case "unknown": object["sourcePath"] = "/unowned"
        default: Issue.record("Unknown mutation")
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: (any Error).self) {
            _ = try SharedMediaCaptureArtifactRequest.decode(data, sha256: SharedMediaAcquisitionEncoding.digest(data))
        }
    }

    @Test func sourceRolesKeepTheirOwnMediaBoundsAndOrigin() throws {
        _ = try request(role: .sourceAudio, origin: .microphone)
        _ = try request(role: .sourceVideo)
        _ = try request(role: .sourceCompanionAudio, origin: .videoAudio)
        _ = try request(origin: .imported)
        #expect(throws: (any Error).self) { try request(role: .preparedImage) }
        #expect(throws: (any Error).self) { try request(role: .sourceAudio, origin: .camera) }
    }
}
