import Foundation

/// Immutable description of one ordinary submission's liability on an existing
/// original. This is not a read, upload, save, migration or unlink capability.
/// The owner must prove the current graph and file identity before admission.
struct SharedMediaOrdinaryHoldRequest: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "ordinaryOriginalHoldV1" }

    /// All holds in one observation bind the same frozen submission and event.
    /// These digests identify canonical owner-prepared bytes, not mutable UI state.
    struct Recipient: Codable, Equatable, Sendable {
        let scanID: UUID
        let submissionGeneration: UUID
        let eventID: UUID
        /// Digest of the complete canonical submission, including media order.
        let observationSHA256: String
        /// Per-source derivative intent digest, deliberately different for
        /// distinct sources. Admission must bind it to the exact frozen entry.
        let preparationSHA256: String

        var jobID: String { OfflineQueueManager.scanIngestionJobId(scanId: scanID.uuidString.lowercased()) }

        func validate() throws {
            guard Set([scanID, submissionGeneration, eventID]).count == 3,
                  [observationSHA256, preparationSHA256].allSatisfy(SharedMediaAcquisitionEncoding.isHash) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    let format: Format
    let id: UUID
    let profile: SharedMediaNativeAppProfile
    let writerEpoch: UUID
    let source: PhotoOriginalReference
    /// Acquisition is historical. Its physical origin may differ from the
    /// source's current logical package after a legitimate share.
    let acquisition: SharedMediaAcquisitionIntent
    let completion: SharedMediaAcquisitionResult
    let recipient: Recipient
    let inventoryRevision: Int64
    let sourcePackageRevision: Int64
    let sourceMembershipRevision: Int64
    let liveCount: Int64
    let countRevision: Int64

    init(id: UUID, profile: SharedMediaNativeAppProfile, writerEpoch: UUID,
         source: PhotoOriginalReference, acquisition: SharedMediaAcquisitionIntent,
         completion: SharedMediaAcquisitionResult, recipient: Recipient,
         inventoryRevision: Int64, sourcePackageRevision: Int64,
         sourceMembershipRevision: Int64, liveCount: Int64, countRevision: Int64) throws {
        format = .v1; self.id = id; self.profile = profile; self.writerEpoch = writerEpoch
        self.source = source; self.acquisition = acquisition; self.completion = completion
        self.recipient = recipient; self.inventoryRevision = inventoryRevision
        self.sourcePackageRevision = sourcePackageRevision; self.sourceMembershipRevision = sourceMembershipRevision
        self.liveCount = liveCount; self.countRevision = countRevision
        try validate()
    }

    func validate() throws {
        try source.validate(); try recipient.validate(); try completion.validate(request: acquisition)
        guard UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
              [profile.physicalBinding, profile.receiptDigest].allSatisfy(SharedMediaAcquisitionEncoding.isHash),
              acquisition.inventoryID == profile.inventoryID, acquisition.inventoryGeneration == profile.generation,
              acquisition.ownerID == profile.ownerID, source.ownerID == profile.ownerID,
              source.assetID == acquisition.assetID, source.assetGeneration == acquisition.assetGeneration,
              inventoryRevision >= completion.inventoryRevision, inventoryRevision < Int64.max,
              sourcePackageRevision >= 0, sourcePackageRevision < Int64.max,
              sourceMembershipRevision >= 0, sourceMembershipRevision < Int64.max,
              source.referenceRevision >= 0, source.referenceRevision < Int64.max,
              liveCount > 0, liveCount < Int64.max, countRevision >= completion.counterRevision,
              countRevision < Int64.max else { throw SharedMediaStorageFailure.conflict }
        _ = try profile.binding
        // The hold is a distinct logical edge, not an alias of a draft, asset,
        // acquisition, account or recipient. Global collisions need a store audit.
        let existing = [profile.ownerID, profile.inventoryID, profile.generation, writerEpoch,
            source.packageID, source.referenceID, source.assetID, source.assetGeneration, source.draftGeneration,
            acquisition.operationID, acquisition.packageID, acquisition.referenceID,
            recipient.scanID, recipient.submissionGeneration, recipient.eventID]
        guard !existing.contains(id) else { throw SharedMediaStorageFailure.conflict }
        if source.referenceID == acquisition.referenceID {
            guard source.packageID == acquisition.packageID, source.draftGeneration == acquisition.draftGeneration,
                  source.referenceRevision == acquisition.initialReferenceRevision,
                  sourcePackageRevision >= completion.packageRevision,
                  sourceMembershipRevision >= completion.membershipRevision else { throw SharedMediaStorageFailure.conflict }
        }
    }

    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes)
    }

    static func decode(_ data: Data, sha256: String) throws -> Self {
        try SharedMediaOrdinaryHoldEncoding.requireDigest(data, sha256: sha256)
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}

/// Bounded, historical local-save postconditions. Construction and decoding
/// do not establish that a transaction committed. Fresh persisted readback must
/// prove the exact queue rows and this receipt under the registered owner.
struct SharedMediaOrdinaryHoldAcceptance: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "ordinaryOriginalHoldAcceptanceV1" }
    let format: Format
    let requestSHA256: String
    let inventoryRevision: Int64
    let countRevision: Int64
    let liveCount: Int64

    init(request: SharedMediaOrdinaryHoldRequest, inventoryRevision: Int64, countRevision: Int64, liveCount: Int64) throws {
        format = .v1; requestSHA256 = SharedMediaAcquisitionEncoding.digest(try request.encoded())
        self.inventoryRevision = inventoryRevision; self.countRevision = countRevision; self.liveCount = liveCount
        try validate(request: request)
    }

    func validate(request: SharedMediaOrdinaryHoldRequest) throws {
        // A single observation transaction increments the inventory once. Each
        // asset may have multiple distinct holds in that transaction; the final
        // counter must include all of them. The transaction proof checks the
        // exact delta; this codec only proves a bounded positive increment.
        guard requestSHA256 == SharedMediaAcquisitionEncoding.digest(try request.encoded()),
              inventoryRevision == (try SharedMediaStoragePolicy.add(request.inventoryRevision, 1)),
              countRevision == (try SharedMediaStoragePolicy.add(request.countRevision, 1)),
              liveCount > request.liveCount,
              liveCount - request.liveCount <= Int64(SharedMediaOrdinaryHoldCohort.maximumHolds) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func encoded(request: SharedMediaOrdinaryHoldRequest) throws -> Data {
        try validate(request: request)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes)
    }

    static func decode(_ data: Data, sha256: String, request: SharedMediaOrdinaryHoldRequest) throws -> Self {
        try SharedMediaOrdinaryHoldEncoding.requireDigest(data, sha256: sha256)
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes)
        guard try value.encoded(request: request) == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}

enum SharedMediaOrdinaryHoldEncoding {
    // Internal bound, within the existing 1 MiB metadata policy. It does not
    // increase physical original capacity or reserve bytes in the inventory.
    static let maximumEnvelopeBytes = 16 * 1_024
    static let maximumRecordBytes = 4 * (maximumEnvelopeBytes + 64)

    static func requireDigest(_ data: Data, sha256: String) throws {
        guard !data.isEmpty, data.count <= maximumEnvelopeBytes else { throw SharedMediaStorageFailure.capacity }
        guard SharedMediaAcquisitionEncoding.isHash(sha256), SharedMediaAcquisitionEncoding.digest(data) == sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    /// Charge stored envelope bytes and digests exactly once; not a SQLite/WAL
    /// measurement, physical byte charge, or approval to persist opaque payloads.
    static func metadataBytes(_ fields: [(Data?, String?)]) throws -> Int64 {
        guard fields.count == 4 else { throw SharedMediaStorageFailure.conflict }
        var total: Int64 = 0
        for (data, digest) in fields {
            switch (data, digest) {
            case (nil, nil): continue
            case (.some(let data), .some(let digest)):
                try requireDigest(data, sha256: digest)
                total = try SharedMediaStoragePolicy.add(total, Int64(data.count + 64))
            default: throw SharedMediaStorageFailure.conflict
            }
        }
        guard total <= maximumRecordBytes else { throw SharedMediaStorageFailure.capacity }
        return total
    }
}
