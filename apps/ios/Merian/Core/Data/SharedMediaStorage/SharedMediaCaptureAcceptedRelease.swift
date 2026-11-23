import Foundation

/// Permanent complete-observation release intent. Its immutable membership and
/// History proof survive every child unlink; terminal state never grants reuse.
struct SharedMediaCaptureAcceptedRelease: Codable, Equatable, Sendable {
    static let maximumBytes = 65_536
    enum Format: String, Codable, Sendable { case v1 = "captureAcceptedReleaseV1" }
    struct Member: Codable, Equatable, Sendable {
        let artifactID: UUID
        let requestSHA256: String
        let stageSHA256: String
        let remoteSHA256: String
        let finalIdentity: String
    }
    let format: Format
    let proof: SharedMediaCaptureReleaseQualification.Proof
    let members: [Member]
    let inventoryRevision: Int64
    var releasedRevision: Int64?

    @MainActor
    init(proof: SharedMediaCaptureReleaseQualification.Proof,
         saved: SharedMediaCaptureSubmissionReceipt.Snapshot, inventoryRevision: Int64) throws {
        guard saved.release == nil, case let .accepted(acceptance) = saved.state else { throw SharedMediaStorageFailure.closed }
        format = .v1; self.proof = proof; self.inventoryRevision = inventoryRevision
        members = try saved.artifacts.map { value in
            guard value.phase == .ready, !value.isRetiring,
                  let stage = value.stage, let remote = value.remoteStage,
                  let finalIdentity = stage.finalIdentity,
                  inventoryRevision > remote.inventoryRevision else { throw SharedMediaStorageFailure.closed }
            return try Member(artifactID: value.request.id, requestSHA256: value.request.digest,
                stageSHA256: SharedMediaAcquisitionEncoding.digest(stage.encoded(request: value.request)),
                remoteSHA256: SharedMediaAcquisitionEncoding.digest(remote.encoded(request: value.request, stage: stage)),
                finalIdentity: finalIdentity)
        }
        try validate(submission: saved.submission, acceptance: acceptance, artifacts: saved.artifacts)
    }

    @MainActor
    func validate(submission: SharedMediaCaptureSubmission, acceptance: SharedMediaCaptureSubmissionAcceptance,
                  artifacts: [SharedMediaCaptureArtifactLedger.Snapshot]) throws {
        guard format == .v1, proof.version == 1,
              proof.submissionSHA256 == SharedMediaAcquisitionEncoding.digest(try submission.encoded()),
              proof.acceptanceSHA256 == SharedMediaAcquisitionEncoding.digest(try acceptance.encoded(submission: submission, artifacts: artifacts)),
              proof.history.ownerID == submission.profile.ownerID, proof.history.observationID == submission.scanID,
              proof.history.intentID != nil, proof.history.provenance == nil,
              SharedMediaAcquisitionEncoding.isHash(proof.fundingSHA256), SharedMediaAcquisitionEncoding.isHash(proof.completionSHA256),
              inventoryRevision > acceptance.inventoryRevision, inventoryRevision < Int64.max,
              releasedRevision.map({ $0 > inventoryRevision && $0 < Int64.max }) ?? true,
              members.count == submission.members.count, artifacts.count == members.count,
              members.map(\.artifactID) == submission.members.map(\.artifactID) else { throw SharedMediaStorageFailure.conflict }
        try proof.history.validate()
        for (member, value) in zip(members, artifacts) {
            guard value.phase == .ready, value.retirement == nil,
                  let stage = value.stage, let remote = value.remoteStage,
                  member.artifactID == value.request.id, member.requestSHA256 == (try value.request.digest),
                  member.stageSHA256 == SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: value.request)),
                  member.remoteSHA256 == SharedMediaAcquisitionEncoding.digest(try remote.encoded(request: value.request, stage: stage)),
                  member.finalIdentity == stage.finalIdentity, inventoryRevision > remote.inventoryRevision else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    var intentSHA256: String {
        get throws {
            var intent = self; intent.releasedRevision = nil
            return try SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(intent, maximum: Self.maximumBytes))
        }
    }

    @MainActor
    func encoded(submission: SharedMediaCaptureSubmission, acceptance: SharedMediaCaptureSubmissionAcceptance,
                 artifacts: [SharedMediaCaptureArtifactLedger.Snapshot]) throws -> Data {
        try validate(submission: submission, acceptance: acceptance, artifacts: artifacts)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    @MainActor
    static func decode(_ data: Data, sha256: String, submission: SharedMediaCaptureSubmission,
                       acceptance: SharedMediaCaptureSubmissionAcceptance,
                       artifacts: [SharedMediaCaptureArtifactLedger.Snapshot]) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256), SharedMediaAcquisitionEncoding.digest(data) == sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumBytes)
        guard try value.encoded(submission: submission, acceptance: acceptance, artifacts: artifacts) == data else {
            throw SharedMediaStorageFailure.conflict
        }
        return value
    }
}

/// Accepted-member authority is deliberately separate from parentless source
/// discard and preparation abort. Every consumer must join the parent intent.
struct SharedMediaCaptureMemberRelease: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "captureAcceptedArtifactReleaseV1" }
    static let maximumBytes = 8192
    let format: Format
    let parentIntentSHA256: String
    let member: SharedMediaCaptureAcceptedRelease.Member
    let inventoryRevision: Int64
    var releasedRevision: Int64?

    func validate(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage,
                  remote: SharedMediaCaptureRemoteStage) throws {
        try request.validate(); try stage.validate(request)
        guard format == .v1, SharedMediaAcquisitionEncoding.isHash(parentIntentSHA256),
              member.artifactID == request.id, member.requestSHA256 == (try request.digest),
              member.stageSHA256 == SharedMediaAcquisitionEncoding.digest(try stage.encoded(request: request)),
              member.remoteSHA256 == SharedMediaAcquisitionEncoding.digest(try remote.encoded(request: request, stage: stage)),
              stage.phase == .complete, member.finalIdentity == stage.finalIdentity,
              inventoryRevision > remote.inventoryRevision, inventoryRevision < Int64.max,
              releasedRevision.map({ $0 > inventoryRevision && $0 < Int64.max }) ?? true else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func encoded(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage,
                 remote: SharedMediaCaptureRemoteStage) throws -> Data {
        try validate(request: request, stage: stage, remote: remote)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    static func decode(_ data: Data, sha256: String, request: SharedMediaCaptureArtifactRequest,
                       stage: SharedMediaCaptureArtifactStage, remote: SharedMediaCaptureRemoteStage) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256), SharedMediaAcquisitionEncoding.digest(data) == sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumBytes)
        guard try value.encoded(request: request, stage: stage, remote: remote) == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
