import Foundation

/// Exact whole-observation membership retained independently of queue cleanup.
/// This envelope does not authorize file I/O, queue admission or execution.
struct SharedMediaCaptureSubmission: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "captureSubmissionV1" }
    struct Member: Codable, Equatable, Sendable {
        let artifactID: UUID
        let mediaID: UUID
        var retainedRequestSHA256: String?
        var retainedStageSHA256: String?
    }
    let format: Format
    let profile: SharedMediaNativeAppProfile
    let writerEpoch: UUID
    let inventoryRevision: Int64
    let rootBindingSHA256: String
    let scanID: UUID
    let generation: UUID
    let eventID: UUID
    let context: SharedMediaCaptureSubmissionContext
    let observation: SharedMediaNativePreparationBlob
    let members: [Member]

    var jobID: String { OfflineQueueManager.scanIngestionJobId(scanId: scanID.uuidString.lowercased()) }
    var identityKey: String {
        SharedMediaOrdinarySubmission.identityKey(ownerID: profile.ownerID, scanID: scanID, generation: generation)
    }

    init(plan: CaptureInitialEvidencePlan, context: SharedMediaCaptureSubmissionContext, profile: SharedMediaNativeAppProfile, writerEpoch: UUID,
         inventoryRevision: Int64, rootBindingSHA256: String, eventID: UUID, artifactIDs: [UUID],
         retainedArtifacts: [SharedMediaCaptureArtifactLedger.Snapshot] = []) throws {
        format = .v1; self.profile = profile; self.writerEpoch = writerEpoch; self.inventoryRevision = inventoryRevision
        self.rootBindingSHA256 = rootBindingSHA256
        scanID = plan.scanID; generation = plan.generation; self.eventID = eventID
        self.context = context
        observation = .init(bytes: try plan.encoded())
        guard plan.ownerID == profile.ownerID, artifactIDs.count == plan.uploads.count else { throw SharedMediaStorageFailure.conflict }
        guard Set(retainedArtifacts.map { $0.request.id }).isSubset(of: Set(artifactIDs)),
              Set(retainedArtifacts.map { $0.request.id }).count == retainedArtifacts.count else { throw SharedMediaStorageFailure.conflict }
        members = try zip(artifactIDs, plan.uploads).map { id, upload in
            guard let retained = retainedArtifacts.first(where: { $0.request.id == id }) else {
                return .init(artifactID: id, mediaID: upload.artifact.mediaID)
            }
            guard retained.phase == .ready, retained.remoteStage == nil, retained.retirement == nil,
                  let stage = retained.stage, stage.phase == .complete, stage.inventoryRevision <= inventoryRevision else {
                throw SharedMediaStorageFailure.conflict
            }
            return try .init(artifactID: id, mediaID: upload.artifact.mediaID,
                retainedRequestSHA256: retained.request.digest,
                retainedStageSHA256: SharedMediaAcquisitionEncoding.digest(stage.encoded(request: retained.request)))
        }
        try validate()
        for retained in retainedArtifacts { try requireMember(retained) }
    }

    func plan() throws -> CaptureInitialEvidencePlan {
        try observation.validate()
        let plan = try CaptureInitialEvidencePlan(ownerID: profile.ownerID, data: observation.bytes)
        guard try plan.encoded() == observation.bytes, plan.scanID == scanID, plan.generation == generation else {
            throw SharedMediaStorageFailure.conflict
        }
        return plan
    }

    func validate() throws {
        let plan = try plan()
        try context.validate(plan: plan)
        _ = try profile.binding
        guard UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
              [profile.physicalBinding, profile.receiptDigest, rootBindingSHA256].allSatisfy(SharedMediaAcquisitionEncoding.isHash),
              inventoryRevision >= 0, inventoryRevision < Int64.max - 2,
              members.count == plan.uploads.count, !members.isEmpty else { throw SharedMediaStorageFailure.conflict }
        let identities = [profile.ownerID, profile.inventoryID, profile.generation, writerEpoch, scanID, generation, eventID]
        var used = Set(identities)
        guard used.count == identities.count else { throw SharedMediaStorageFailure.conflict }
        for (member, upload) in zip(members, plan.uploads) {
            guard member.mediaID == upload.artifact.mediaID, used.insert(member.mediaID).inserted,
                  used.insert(member.artifactID).inserted else { throw SharedMediaStorageFailure.conflict }
            guard (member.retainedRequestSHA256 == nil) == (member.retainedStageSHA256 == nil),
                  [member.retainedRequestSHA256, member.retainedStageSHA256].compactMap({ $0 })
                    .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.conflict }
        }
        // Reserved server DSP outputs are not local files and cannot alias an
        // artifact ID. The plan parser already checks their media uniqueness.
        for node in plan.items {
            let serverID: UUID?
            switch node {
            case .audio(let audio): serverID = audio.preparedMediaID
            case .video(let video): serverID = video.audio?.preparedMediaID
            default: serverID = nil
            }
            if let serverID, !used.insert(serverID).inserted { throw SharedMediaStorageFailure.conflict }
        }
    }

    func artifact(mediaID: UUID) throws -> SharedMediaCaptureArtifactInput {
        try validate()
        let plan = try plan()
        guard let member = members.first(where: { $0.mediaID == mediaID }),
              let upload = plan.uploads.first(where: { $0.artifact.mediaID == mediaID }),
              let role = SharedMediaCaptureArtifactRequest.Role(rawValue: upload.role.rawValue) else { throw SharedMediaStorageFailure.conflict }
        return .init(id: member.artifactID, scanID: scanID, submissionGeneration: generation, mediaID: mediaID,
            planSHA256: observation.sha256, itemIndex: upload.itemIndex, role: role, frameIndex: upload.frameIndex,
            contentType: upload.artifact.contentType, byteCount: Int64(upload.artifact.byteCount), sha256: upload.artifact.sha256)
    }

    func requireMember(_ artifact: SharedMediaCaptureArtifactLedger.Snapshot) throws {
        let request = artifact.request
        let input = try self.artifact(mediaID: request.mediaID)
        guard let member = members.first(where: { $0.artifactID == request.id }) else { throw SharedMediaStorageFailure.conflict }
        guard request.profile == profile, request.rootBindingSHA256 == rootBindingSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        switch request.format {
        case .v1:
            guard input.matches(request) else { throw SharedMediaStorageFailure.conflict }
            if member.retainedRequestSHA256 == nil {
                guard request.inventoryRevision > inventoryRevision else { throw SharedMediaStorageFailure.conflict }
            }
        case .draftSourceV1:
            guard input.bindsSource(request), artifact.phase == .ready, let stage = artifact.stage,
                  stage.phase == .complete, stage.inventoryRevision <= inventoryRevision else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        if let digest = member.retainedRequestSHA256 {
            guard digest == (try request.digest), artifact.phase == .ready, artifact.retirement == nil,
                  let stage = artifact.stage, stage.phase == .complete, stage.inventoryRevision <= inventoryRevision,
                  member.retainedStageSHA256 == (try SharedMediaAcquisitionEncoding.digest(stage.encoded(request: request))) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// One complete pending observation, including bounded future metadata.
    /// This is logical package accounting; physical bytes are charged elsewhere.
    var packageBytes: Int64 {
        get throws {
            var total = Int64(try encoded().count + 128 + SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes)
            for upload in try plan().uploads {
                total = try SharedMediaStoragePolicy.add(total, SharedMediaStoragePolicy.add(Int64(upload.artifact.byteCount),
                    Int64(2 * SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 128 + 160
                        + SharedMediaCaptureRemoteStage.maximumBytes + 64)))
            }
            guard total <= PhotoPreparationPolicy.package else { throw SharedMediaStorageFailure.capacity }
            return total
        }
    }

    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata) - SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes - 128)
    }
    static func decode(_ data: Data, sha256: String) throws -> Self {
        guard data.count <= PhotoPreparationPolicy.metadata, SharedMediaAcquisitionEncoding.isHash(sha256),
              SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
