import Foundation

extension CaptureInitialEvidencePlan {
    func artifactInput(mediaID: UUID, id: UUID) throws -> SharedMediaCaptureArtifactInput {
        guard let upload = uploads.first(where: { $0.artifact.mediaID == mediaID }),
              let role = SharedMediaCaptureArtifactRequest.Role(rawValue: upload.role.rawValue) else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(id: id, scanID: scanID, submissionGeneration: generation, mediaID: mediaID,
            planSHA256: SharedMediaAcquisitionEncoding.digest(try encoded()), itemIndex: upload.itemIndex,
            role: role, frameIndex: upload.frameIndex, contentType: upload.artifact.contentType,
            byteCount: Int64(upload.artifact.byteCount), sha256: upload.artifact.sha256)
    }
    /// The registered owner supplies reservation identities and root facts.
    /// Selecting a server-created audio ID cannot manufacture a local liability.
    func artifactRequest(mediaID: UUID, id: UUID, profile: SharedMediaNativeAppProfile,
                         writerEpoch: UUID, rootBindingSHA256: String, inventoryRevision: Int64,
                         allocationID: UUID, referenceID: UUID, leaseID: UUID) throws -> SharedMediaCaptureArtifactRequest {
        guard profile.ownerID == ownerID,
              let upload = uploads.first(where: { $0.artifact.mediaID == mediaID }),
              let role = SharedMediaCaptureArtifactRequest.Role(rawValue: upload.role.rawValue) else {
            throw SharedMediaStorageFailure.conflict
        }
        return try .init(id: id, profile: profile, writerEpoch: writerEpoch,
            scanID: scanID, submissionGeneration: generation,
            planSHA256: SharedMediaAcquisitionEncoding.digest(encoded()), rootBindingSHA256: rootBindingSHA256,
            inventoryRevision: inventoryRevision, mediaID: mediaID, itemIndex: upload.itemIndex,
            role: role, frameIndex: upload.frameIndex, contentType: upload.artifact.contentType,
            byteCount: Int64(upload.artifact.byteCount), sha256: upload.artifact.sha256,
            allocationID: allocationID, referenceID: referenceID, leaseID: leaseID)
    }
}
