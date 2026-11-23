import Foundation

/// Historical complete-set receipt; only the atomic admission owner can
/// establish that queue, job, event and this receipt committed together.
struct SharedMediaCaptureSubmissionAcceptance: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "captureSubmissionAcceptanceV1" }
    struct Member: Codable, Equatable, Sendable {
        let artifactID: UUID
        let requestSHA256: String
        let stageSHA256: String
    }
    let format: Format
    let requestSHA256: String
    let inventoryRevision: Int64
    let members: [Member]

    @MainActor
    init(submission: SharedMediaCaptureSubmission, artifacts: [SharedMediaCaptureArtifactLedger.Snapshot],
         inventoryRevision: Int64) throws {
        try submission.validate()
        guard artifacts.count == submission.members.count,
              inventoryRevision > submission.inventoryRevision else { throw SharedMediaStorageFailure.conflict }
        format = .v1; self.inventoryRevision = inventoryRevision
        requestSHA256 = SharedMediaAcquisitionEncoding.digest(try submission.encoded())
        members = try zip(submission.members, artifacts).map { member, artifact in
            let request = artifact.request
            try submission.requireMember(artifact)
            guard artifact.phase == .ready, let stage = artifact.stage, stage.phase == .complete,
                  request.id == member.artifactID, request.profile == submission.profile,
                  request.rootBindingSHA256 == submission.rootBindingSHA256,
                  inventoryRevision > stage.inventoryRevision else {
                throw SharedMediaStorageFailure.conflict
            }
            return try Member(artifactID: request.id, requestSHA256: request.digest,
                stageSHA256: SharedMediaAcquisitionEncoding.digest(stage.encoded(request: request)))
        }
    }

    @MainActor
    func encoded(submission: SharedMediaCaptureSubmission,
                 artifacts: [SharedMediaCaptureArtifactLedger.Snapshot]) throws -> Data {
        guard try self == Self(submission: submission, artifacts: artifacts, inventoryRevision: inventoryRevision) else {
            throw SharedMediaStorageFailure.conflict
        }
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes)
    }

    @MainActor
    static func decode(_ data: Data, sha256: String, submission: SharedMediaCaptureSubmission,
                       artifacts: [SharedMediaCaptureArtifactLedger.Snapshot]) throws -> Self {
        guard data.count <= SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes,
              SharedMediaAcquisitionEncoding.isHash(sha256), SharedMediaAcquisitionEncoding.digest(data) == sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes)
        guard try value.encoded(submission: submission, artifacts: artifacts) == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
