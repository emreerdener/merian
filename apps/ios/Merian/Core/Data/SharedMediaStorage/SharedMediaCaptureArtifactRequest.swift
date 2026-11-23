import Foundation

/// Feature-supplied immutable content facts. Storage, epoch and reservation
/// identities are supplied by the registered owner at first materialization.
struct SharedMediaCaptureArtifactInput: Equatable, Sendable {
    let id: UUID, scanID: UUID, submissionGeneration: UUID, mediaID: UUID
    let planSHA256: String
    let itemIndex: Int
    let role: SharedMediaCaptureArtifactRequest.Role
    let frameIndex: Int?
    let contentType: String
    let byteCount: Int64
    let sha256: String

    func matches(_ request: SharedMediaCaptureArtifactRequest) -> Bool {
        request.format == .v1 && id == request.id && scanID == request.scanID && submissionGeneration == request.submissionGeneration
            && mediaID == request.mediaID && planSHA256 == request.planSHA256 && itemIndex == request.itemIndex
            && role == request.role && frameIndex == request.frameIndex && contentType == request.contentType
            && byteCount == request.byteCount && sha256 == request.sha256
    }

    /// Used only when an immutable parent binds an already-ready source.
    /// Draft source ordinals and request bytes never change when UI order changes.
    func bindsSource(_ request: SharedMediaCaptureArtifactRequest) -> Bool {
        request.format == .draftSourceV1 && id == request.id && scanID == request.scanID &&
            submissionGeneration == request.submissionGeneration && mediaID == request.mediaID &&
            role == request.role && frameIndex == nil && request.frameIndex == nil &&
            contentType == request.contentType && byteCount == request.byteCount && sha256 == request.sha256
    }
}

/// Immutable reservation facts for one locally materialized capture role.
/// This is a description, never a file, save, upload or retirement capability.
struct SharedMediaCaptureArtifactRequest: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable {
        case v1 = "captureArtifactRequestV1"
        case draftSourceV1 = "draftSourceV1"
    }
    enum Role: String, Codable, Sendable {
        case sourceImage = "source_image", preparedImage = "prepared_image"
        case sourceAudio = "source_audio", sourceVideo = "source_video"
        case playbackVideo = "playback_video", inferenceFrame = "inference_frame"
        case sourceCompanionAudio = "source_companion_audio"

        func require(contentType: String, byteCount: Int64, frameIndex: Int?) throws {
            let types: Set<String>, limit: Int64
            switch self {
            case .sourceImage:
                types = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]; limit = 33_554_432
            case .preparedImage, .inferenceFrame:
                types = ["image/jpeg", "image/png"]; limit = 5_242_880
            case .sourceAudio, .sourceCompanionAudio:
                types = ["audio/wav"]; limit = 2_700_000
            case .sourceVideo, .playbackVideo:
                types = ["video/mp4"]; limit = 12_582_912
            }
            guard types.contains(contentType), (contentType == "audio/wav" ? 46 : 1)...limit ~= byteCount else {
                throw SharedMediaStorageFailure.conflict
            }
            if self == .inferenceFrame {
                guard let frameIndex, (0..<5).contains(frameIndex) else { throw SharedMediaStorageFailure.conflict }
            } else if frameIndex != nil { throw SharedMediaStorageFailure.conflict }
        }
    }

    static let maximumEnvelopeBytes = 8192
    let format: Format
    let id: UUID
    let profile: SharedMediaNativeAppProfile
    let writerEpoch: UUID
    let scanID: UUID
    let submissionGeneration: UUID
    let planSHA256: String?
    let draftSource: SharedMediaCaptureDraftSourceContext?
    let rootBindingSHA256: String
    let inventoryRevision: Int64
    let mediaID: UUID
    let itemIndex: Int
    let role: Role
    let frameIndex: Int?
    let contentType: String
    let byteCount: Int64
    let sha256: String
    let allocationID: UUID
    let referenceID: UUID
    let leaseID: UUID
    var schemaVersion: Int { format == .v1 ? 1 : 2 }

    /// Flat, generated names only: no caller-controlled path can be persisted.
    var finalName: String { id.uuidString.lowercased() }
    var partialName: String { finalName + ".partial" }

    init(id: UUID, profile: SharedMediaNativeAppProfile, writerEpoch: UUID,
         scanID: UUID, submissionGeneration: UUID, planSHA256: String, rootBindingSHA256: String,
         inventoryRevision: Int64, mediaID: UUID, itemIndex: Int, role: Role, frameIndex: Int?,
         contentType: String, byteCount: Int64, sha256: String,
         allocationID: UUID, referenceID: UUID, leaseID: UUID) throws {
        format = .v1; draftSource = nil; self.id = id; self.profile = profile; self.writerEpoch = writerEpoch
        self.scanID = scanID; self.submissionGeneration = submissionGeneration; self.planSHA256 = planSHA256
        self.rootBindingSHA256 = rootBindingSHA256; self.inventoryRevision = inventoryRevision
        self.mediaID = mediaID; self.itemIndex = itemIndex; self.role = role; self.frameIndex = frameIndex
        self.contentType = contentType; self.byteCount = byteCount; self.sha256 = sha256
        self.allocationID = allocationID; self.referenceID = referenceID; self.leaseID = leaseID
        try validate()
    }

    init(source: SharedMediaCaptureDraftSourceInput, profile: SharedMediaNativeAppProfile, writerEpoch: UUID,
         rootBindingSHA256: String, inventoryRevision: Int64, allocationID: UUID, referenceID: UUID, leaseID: UUID) throws {
        format = .draftSourceV1; planSHA256 = nil; draftSource = source.context
        id = source.id; self.profile = profile; self.writerEpoch = writerEpoch
        scanID = source.scanID; submissionGeneration = source.submissionGeneration
        self.rootBindingSHA256 = rootBindingSHA256; self.inventoryRevision = inventoryRevision
        mediaID = source.mediaID; itemIndex = source.itemIndex; role = source.role; frameIndex = nil
        contentType = source.contentType; byteCount = source.byteCount; sha256 = source.sha256
        self.allocationID = allocationID; self.referenceID = referenceID; self.leaseID = leaseID
        try validate()
    }

    func validate() throws {
        let ids = [id, profile.ownerID, profile.inventoryID, profile.generation, writerEpoch,
            scanID, submissionGeneration, mediaID, allocationID, referenceID, leaseID]
        guard Set(ids).count == ids.count, (0..<64).contains(itemIndex),
              inventoryRevision >= 0, inventoryRevision < Int64.max - 2,
              UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
              [rootBindingSHA256, sha256, profile.physicalBinding, profile.receiptDigest]
                .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.conflict }
        switch format {
        case .v1:
            guard let planSHA256, SharedMediaAcquisitionEncoding.isHash(planSHA256), draftSource == nil else {
                throw SharedMediaStorageFailure.conflict
            }
        case .draftSourceV1:
            guard planSHA256 == nil, frameIndex == nil, let draftSource else { throw SharedMediaStorageFailure.conflict }
            try draftSource.validate(role: role)
        }
        _ = try profile.binding
        try role.require(contentType: contentType, byteCount: byteCount, frameIndex: frameIndex)
    }

    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumEnvelopeBytes)
    }
    var digest: String { get throws { try SharedMediaAcquisitionEncoding.digest(encoded()) } }

    static func decode(_ data: Data, sha256: String) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256), data.count <= maximumEnvelopeBytes,
              SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumEnvelopeBytes)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
