import Foundation

/// Versioned durable binding around the existing canonical observation body.
/// Decoding describes a submission; it grants no admission, file or cleanup authority.
struct SharedMediaOrdinarySubmission: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case photoV1 = "ordinaryPhotoSubmissionV1" }
    struct Member: Codable, Equatable, Sendable {
        let holdID: UUID
        let sourceReferenceID: UUID
        let requestSHA256: String
        let preparationSHA256: String
    }

    let format: Format
    let profile: SharedMediaNativeAppProfile
    let writerEpoch: UUID
    let scanID: UUID
    let generation: UUID
    let eventID: UUID
    let observation: SharedMediaNativePreparationBlob
    /// Frozen media order, never UUID/accounting order.
    let members: [Member]

    var jobID: String { OfflineQueueManager.scanIngestionJobId(scanId: scanID.uuidString.lowercased()) }
    var identityKey: String { Self.identityKey(ownerID: profile.ownerID, scanID: scanID, generation: generation) }
    static func identityKey(ownerID: UUID, scanID: UUID, generation: UUID) -> String {
        [ownerID, scanID, generation].map { $0.uuidString.lowercased() }.joined(separator: ":")
    }

    init(binding: SharedMediaOrdinaryPhotoHoldBinding) throws {
        guard let first = binding.orderedRequests.first else { throw SharedMediaStorageFailure.conflict }
        format = .photoV1; profile = first.profile; writerEpoch = first.writerEpoch
        scanID = first.recipient.scanID; generation = first.recipient.submissionGeneration
        eventID = first.recipient.eventID; observation = binding.submission
        members = try binding.orderedRequests.map {
            Member(holdID: $0.id, sourceReferenceID: $0.source.referenceID,
                   requestSHA256: SharedMediaAcquisitionEncoding.digest(try $0.encoded()),
                   preparationSHA256: $0.recipient.preparationSHA256)
        }
        try validate()
    }

    func validate() throws {
        try observation.validate()
        let frozen = try SharedMediaNativeFrozenCohort.decode(observation.bytes)
        guard UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
              [profile.physicalBinding, profile.receiptDigest].allSatisfy(SharedMediaAcquisitionEncoding.isHash),
              frozen.ownerID == profile.ownerID, Set([scanID, generation, eventID]).count == 3,
              members.count == frozen.entries.count,
              Set(members.map(\.holdID)).count == members.count,
              Set(members.map(\.sourceReferenceID)).count == members.count else {
            throw SharedMediaStorageFailure.conflict
        }
        _ = try profile.binding
        for (member, entry) in zip(members, frozen.entries) {
            let source = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original.reference
            guard member.sourceReferenceID == source.referenceID,
                  member.preparationSHA256 == entry.intent.sha256,
                  SharedMediaAcquisitionEncoding.isHash(member.requestSHA256),
                  ![profile.ownerID, profile.inventoryID, profile.generation, writerEpoch,
                    scanID, generation, eventID, source.packageID, source.draftGeneration,
                    source.referenceID, source.assetID, source.assetGeneration].contains(member.holdID) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// Correlates every immutable request, including its original/acquisition identity.
    /// The caller must separately establish current graph, file and committed-save facts.
    func validate(holds: SharedMediaOrdinaryHoldCohort) throws {
        let binding = try SharedMediaOrdinaryPhotoHoldBinding(holds: holds, submission: observation)
        guard try Self(binding: binding) == self else { throw SharedMediaStorageFailure.conflict }
    }

    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata))
    }
    static func decode(_ data: Data, sha256: String) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256),
              data.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        guard SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
