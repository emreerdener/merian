import Foundation

/// Unconsumed descriptive codec. Canonical decoding is not an ownership proof,
/// durable acceptance, save-closure result, reservation or mutation authority.
struct SharedMediaNativeReleaseStartRequest: Codable, Equatable, Sendable {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Header = SharedMediaNativeAppEligibility.Header
    enum Format: String, Codable, Sendable { case v1 = "nativeReceivingReleaseStartV1" }
    enum PriorSidecar: String, Codable, Sendable { case absent }

    let format: Format
    let profile: SharedMediaNativeAppProfile
    let releaseID: UUID, packageID: UUID, draftGeneration: UUID
    let operationID: UUID, queueID: UUID, observationID: UUID, bindingID: UUID, generation: UUID, eventID: UUID
    let receivedSchemaVersion: Int
    let receivedPhase: String
    let receivedRevision: Int64
    let priorSidecar: PriorSidecar
    let preparedSHA256: String, receivedSHA256: String
    /// The receiving transaction request digest; never this sidecar's digest.
    let receivingRequestSHA256: String, cohortSHA256: String
    /// Historical staging evidence, never the later release Plan's current header.
    let stagePreHeader: Header

    var postStageHeader: Header { get throws { try SharedMediaNativeAppMetadataFacts.successor(stagePreHeader) } }

    init(prepared: Intent.Prepared, received: Intent.Received, stagePreHeader: Header, releaseID: UUID) throws {
        _ = try received.reconstruct(prepared)
        guard prepared.version == 2, let revision = prepared.intentRevision else { throw SharedMediaStorageFailure.closed }
        let predecessor = received.preHeader
        guard stagePreHeader.inventory.generation == predecessor.inventory.generation,
              stagePreHeader.inventory.revision > predecessor.inventory.revision,
              stagePreHeader.bootstrapID == predecessor.bootstrapID,
              stagePreHeader.bootstrapGeneration == predecessor.bootstrapGeneration,
              stagePreHeader.bootstrapContract == predecessor.bootstrapContract,
              stagePreHeader.bootstrapRevision == predecessor.bootstrapRevision else { throw SharedMediaStorageFailure.stale }
        format = .v1; profile = prepared.profile; self.releaseID = releaseID
        packageID = prepared.package.id; draftGeneration = prepared.package.generation
        operationID = prepared.operationID; queueID = prepared.queueID; observationID = prepared.observationID
        bindingID = prepared.bindingID; generation = prepared.generation; eventID = prepared.eventID
        receivedSchemaVersion = 2; receivedPhase = "received"
        receivedRevision = try SharedMediaStoragePolicy.add(revision, 1); priorSidecar = .absent
        preparedSHA256 = SharedMediaAcquisitionEncoding.digest(try prepared.encoded())
        receivedSHA256 = SharedMediaAcquisitionEncoding.digest(try received.encoded(prepared: prepared))
        receivingRequestSHA256 = received.requestSHA256; cohortSHA256 = prepared.cohort.sha256
        self.stagePreHeader = stagePreHeader
        try validate()
        // Locally visible collisions are rejected here. Acquisition identities
        // and all other operations still require the future complete graph audit.
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        for entry in cohort.entries {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let original = intent.preparation.original.reference
            let identities = [intent.pairID, original.assetID, original.referenceID]
                + [intent.ai, intent.display].flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] }
            guard !identities.contains(releaseID) else { throw SharedMediaStorageFailure.conflict }
        }
    }

    /// Reconstruct the immutable association. The caller must separately prove
    /// exact persisted row fields, sidecar absence/presence and current fences.
    func requireMatch(prepared: Intent.Prepared, received: Intent.Received) throws {
        guard self == (try Self(prepared: prepared, received: received,
            stagePreHeader: stagePreHeader, releaseID: releaseID)) else { throw SharedMediaStorageFailure.conflict }
    }

    func validate() throws {
        guard receivedSchemaVersion == 2, receivedPhase == "received",
              receivedRevision > 0, receivedRevision <= Int64.max - 2,
              UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
              [profile.physicalBinding, profile.receiptDigest, preparedSHA256, receivedSHA256,
               receivingRequestSHA256, cohortSHA256].allSatisfy(SharedMediaAcquisitionEncoding.isHash),
              stagePreHeader.inventory.generation == profile.generation,
              stagePreHeader.inventory.revision >= 0, stagePreHeader.inventory.revision <= Int64.max - 2,
              stagePreHeader.inventory.phase == SharedMediaNativeAppProfile.phase,
              stagePreHeader.inventory.cursor.isEmpty,
              stagePreHeader.bootstrapID == profile.inventoryID,
              stagePreHeader.bootstrapGeneration == profile.generation,
              stagePreHeader.bootstrapContract == 2, stagePreHeader.bootstrapRevision >= 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        _ = try profile.binding; _ = try postStageHeader
        let ids = [releaseID, operationID, queueID, observationID, bindingID, generation, eventID]
        guard Set(ids).count == ids.count,
              ![packageID, draftGeneration, profile.ownerID, profile.inventoryID, profile.generation].contains(releaseID) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func encoded() throws -> Data {
        try validate()
        let bytes = try SharedMediaNativeDraftEnvelope.bytes(self)
        guard bytes.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    static func decode(_ bytes: Data, sha256: String) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256) else { throw SharedMediaStorageFailure.conflict }
        _ = try metadataCharge(dataByteCount: Int64(bytes.count))
        guard SharedMediaAcquisitionEncoding.digest(bytes) == sha256 else { throw SharedMediaStorageFailure.conflict }
        return try decode(bytes)
    }

    /// Shared exact data-plus-digest cap for encoding and external decoding.
    /// This describes serialized liability, not a reservation or valid payload.
    static func metadataCharge(dataByteCount: Int64) throws -> Int64 {
        guard dataByteCount >= 0 else { throw SharedMediaStorageFailure.conflict }
        let total = try PhotoPreparationPolicy.add([dataByteCount, 64])
        guard total <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        return total
    }

    struct Encoding: Equatable, Sendable {
        let data: Data
        let sha256: String
        /// Serialized data plus stored digest, not a SQLite/WAL footprint claim.
        let metadataBytes: Int64
        fileprivate init(_ data: Data) throws {
            self.data = data; sha256 = SharedMediaAcquisitionEncoding.digest(data)
            metadataBytes = try SharedMediaNativeReleaseStartRequest.metadataCharge(dataByteCount: Int64(data.count))
        }
    }

    func encoding() throws -> Encoding { try Encoding(encoded()) }
}
