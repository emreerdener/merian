import Foundation
@testable import Merian
import Testing

struct CaptureArtifactRetirementValueTests {
    let partial = "1:42:0:100:0:100:0"
    let final = "1:42:128:101:0:101:0"

    @Test func cleanupIntentKeepsIdentityThroughRelease() throws {
        let request = try CaptureDraftSourceRequestTests().request()
        let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: 3,
            partialIdentity: partial, finalIdentity: final)
        let intent = try SharedMediaCaptureArtifactRetirement(request: request, stage: stage,
            inventoryRevision: 4, partialIdentity: nil, finalIdentity: final)
        let released = try intent.releasing(at: 5, request: request, stage: stage)
        #expect(released.finalIdentity == intent.finalIdentity)
        #expect(released.inventoryRevision == intent.inventoryRevision)
        #expect(released.releasedRevision == 5)
        let data = try released.encoded(request: request, stage: stage)
        #expect(try SharedMediaCaptureArtifactRetirement.decode(data,
            sha256: SharedMediaAcquisitionEncoding.digest(data), request: request, stage: stage) == released)
        #expect(throws: (any Error).self) { try released.releasing(at: 6, request: request, stage: stage) }
    }

    @Test(arguments: ["inode", "both", "revision", "missing", "malformed"])
    func completedSourceCannotChangeItsDeletionProof(_ mutation: String) throws {
        let request = try CaptureDraftSourceRequestTests().request()
        let stage = try SharedMediaCaptureArtifactStage(request: request, inventoryRevision: 3,
            partialIdentity: partial, finalIdentity: final)
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureArtifactRetirement(request: request, stage: stage,
                inventoryRevision: mutation == "revision" ? 3 : 4,
                partialIdentity: mutation == "both" ? partial : nil,
                finalIdentity: mutation == "missing" ? nil : mutation == "inode" ? "1:43:128:101:0:101:0"
                    : mutation == "malformed" ? "invalid" : final)
        }
    }

    @Test func unrecordedPartialMayOnlyBeAnEmptyCleanupTarget() throws {
        let request = try CaptureDraftSourceRequestTests().request()
        _ = try SharedMediaCaptureArtifactRetirement(request: request, stage: nil,
            inventoryRevision: 2, partialIdentity: partial, finalIdentity: nil)
        _ = try SharedMediaCaptureArtifactRetirement(request: request, stage: nil,
            inventoryRevision: 2, partialIdentity: nil, finalIdentity: nil)
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureArtifactRetirement(request: request, stage: nil,
                inventoryRevision: 2, partialIdentity: final, finalIdentity: nil)
        }
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureArtifactRetirement(request: request, stage: nil,
                inventoryRevision: 2, partialIdentity: nil, finalIdentity: final)
        }
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureArtifactRetirement(request: request, stage: nil,
                inventoryRevision: 1, partialIdentity: nil, finalIdentity: nil)
        }
    }
}
