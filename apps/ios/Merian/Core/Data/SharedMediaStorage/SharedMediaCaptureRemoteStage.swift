import Foundation

/// Saved acknowledgement of one authenticated private upload. This binds the
/// immutable local request and completed file receipt; it grants neither final
/// inference permission nor original disposal authority.
struct SharedMediaCaptureRemoteStage: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "captureRemoteStageV1" }
    static let maximumBytes = 2048
    let format: Format
    let artifactRequestSHA256: String
    let physicalStageSHA256: String
    let serverRequestSHA256: String
    let inventoryRevision: Int64

    init(receipt: CaptureStageReceipt, request: SharedMediaCaptureArtifactRequest,
         stage: SharedMediaCaptureArtifactStage, inventoryRevision: Int64,
         submission: SharedMediaCaptureSubmission? = nil) throws {
        guard receipt.ownerID == request.profile.ownerID, receipt.scanID == request.scanID,
              receipt.generation == request.submissionGeneration, receipt.mediaID == request.mediaID else {
            throw SharedMediaStorageFailure.conflict
        }
        if request.format == .draftSourceV1 {
            guard let submission, receipt.planSHA256 == submission.observation.sha256 else { throw SharedMediaStorageFailure.conflict }
            try submission.requireMember(.init(request: request, phase: .ready, stage: stage, metadataBytes: 0))
        } else if receipt.planSHA256 != request.planSHA256 { throw SharedMediaStorageFailure.conflict }
        format = .v1
        artifactRequestSHA256 = try request.digest
        physicalStageSHA256 = try SharedMediaAcquisitionEncoding.digest(stage.encoded(request: request))
        serverRequestSHA256 = receipt.requestSHA256
        self.inventoryRevision = inventoryRevision
        try validate(request: request, stage: stage)
    }

    func validate(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage) throws {
        guard format == .v1, stage.phase == .complete, inventoryRevision > stage.inventoryRevision,
              SharedMediaAcquisitionEncoding.isHash(serverRequestSHA256),
              artifactRequestSHA256 == (try request.digest),
              physicalStageSHA256 == (try SharedMediaAcquisitionEncoding.digest(stage.encoded(request: request))) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func encoded(request: SharedMediaCaptureArtifactRequest, stage: SharedMediaCaptureArtifactStage) throws -> Data {
        try validate(request: request, stage: stage)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    static func decode(_ data: Data, sha256: String, request: SharedMediaCaptureArtifactRequest,
                       stage: SharedMediaCaptureArtifactStage) throws -> Self {
        guard data.count <= maximumBytes, SharedMediaAcquisitionEncoding.isHash(sha256),
              SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumBytes)
        guard try value.encoded(request: request, stage: stage) == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
