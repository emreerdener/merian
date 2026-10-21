import Foundation

/// Descriptive release values only. Production slot dispatch deliberately does
/// not accept these phases yet. No decoded value authorizes deletion or a save.
enum SharedMediaNativeReceivingReleaseValues {
    typealias Intent = SharedMediaNativeReceivingIntent

    struct Output: Codable, Equatable, Sendable {
        let workID: UUID, assetID: UUID, generation: UUID, referenceID: UUID, leaseID: UUID
        init(_ value: SharedMediaDerivativeInput) {
            workID = value.id; assetID = value.assetID; generation = value.assetGeneration
            referenceID = value.referenceID; leaseID = value.leaseID
        }
        var identities: [UUID] { [workID, assetID, referenceID, leaseID] }
    }

    struct Target: Codable, Equatable, Sendable {
        let pairID: UUID
        let original: PhotoOriginalReference
        /// Also the retained original's shared lease identity. It belongs to the
        /// physical origin, which may differ from this logical package.
        let acquisitionID: UUID
        let ai: Output, display: Output
        let intentSHA256: String
        let originalIdentitySHA256: String, aiIdentitySHA256: String, displayIdentitySHA256: String

        init(_ entry: SharedMediaNativeFrozenEntry, acquisitionID: UUID) throws {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            pairID = intent.pairID; original = intent.preparation.original.reference
            self.acquisitionID = acquisitionID; ai = Output(intent.ai); display = Output(intent.display)
            intentSHA256 = entry.intent.sha256
            originalIdentitySHA256 = digest(try intent.preparation.original.descriptor.encoded())
            aiIdentitySHA256 = digest(try entry.aiDescriptor.encoded())
            displayIdentitySHA256 = digest(try entry.displayDescriptor.encoded())
        }
        var identities: [UUID] {
            [pairID, original.assetID, original.referenceID, acquisitionID] + ai.identities + display.identities
        }
    }

    struct Plan: Codable, Equatable, Sendable {
        enum Format: String, Codable, Sendable { case releasing = "nativeReceivingReleasingV1" }
        let format: Format
        let profile: SharedMediaNativeAppProfile
        let releaseID: UUID
        let operationID: UUID, queueID: UUID, observationID: UUID, bindingID: UUID, generation: UUID, eventID: UUID
        let preparedRevision: Int64
        let preHeader: SharedMediaNativeAppEligibility.Header
        let package: Intent.PackageFence
        let member: Intent.MemberFence
        let preparedSHA256: String, receivedSHA256: String, requestSHA256: String, cohortSHA256: String
        let targets: [Target]

        var receivedRevision: Int64 { get throws { try SharedMediaStoragePolicy.add(preparedRevision, 1) } }
        var releasingRevision: Int64 { get throws { try SharedMediaStoragePolicy.add(preparedRevision, 2) } }
        var jobID: String { "scan-ingestion:" + queueID.uuidString.lowercased() }

        init(prepared: Intent.Prepared, received: Intent.Received,
             header: SharedMediaNativeAppEligibility.Header, releaseID: UUID,
             acquisitionIDs: [UUID]) throws {
            let request = try received.reconstruct(prepared)
            guard prepared.version == 2, let revision = prepared.intentRevision,
                  (revision == 0 && prepared.restagedFromSHA256 == nil) ||
                    (revision > 0 && prepared.restagedFromSHA256 != nil),
                  request.cohort.format == .intentReceiving else { throw SharedMediaStorageFailure.closed }
            let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
            guard acquisitionIDs.count == cohort.entries.count else { throw SharedMediaStorageFailure.conflict }
            let receivedHeader = received.preHeader
            guard header.inventory.generation == receivedHeader.inventory.generation,
                  header.inventory.revision > receivedHeader.inventory.revision,
                  header.bootstrapID == receivedHeader.bootstrapID,
                  header.bootstrapGeneration == receivedHeader.bootstrapGeneration,
                  header.bootstrapContract == receivedHeader.bootstrapContract,
                  header.bootstrapRevision == receivedHeader.bootstrapRevision else {
                throw SharedMediaStorageFailure.stale
            }
            format = .releasing; profile = prepared.profile; self.releaseID = releaseID
            operationID = prepared.operationID; queueID = prepared.queueID; observationID = prepared.observationID
            bindingID = prepared.bindingID; generation = prepared.generation; eventID = prepared.eventID
            preparedRevision = revision; preHeader = header
            package = Intent.PackageFence(try request.frozenPackage()); member = Intent.MemberFence(prepared.member)
            preparedSHA256 = received.preparedSHA256
            receivedSHA256 = SharedMediaAcquisitionEncoding.digest(try received.encoded(prepared: prepared))
            requestSHA256 = received.requestSHA256; cohortSHA256 = prepared.cohort.sha256
            targets = try zip(cohort.entries, acquisitionIDs).map { try Target($0.0, acquisitionID: $0.1) }
            try validate()
        }

        func encoded() throws -> Data {
            try validate(); return try SharedMediaNativeDraftEnvelope.bytes(self)
        }
        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }; return value
        }

        /// Exact origin binding is distinct from structural decoding. Acquisition
        /// IDs must still be read from the authoritative original ledger by the
        /// future owner; a caller-supplied list is not an ownership proof.
        func requireMatch(prepared: Intent.Prepared, received: Intent.Received,
                          acquisitionIDs: [UUID]) throws {
            guard self == (try Self(prepared: prepared, received: received, header: preHeader,
                releaseID: releaseID, acquisitionIDs: acquisitionIDs)) else { throw SharedMediaStorageFailure.conflict }
        }

        func validate() throws {
            guard preparedRevision >= 0,
                  (try SharedMediaStoragePolicy.add(preparedRevision, 3)) <= Int64.max,
                  UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
                  hashes([profile.physicalBinding, profile.receiptDigest, preparedSHA256,
                          receivedSHA256, requestSHA256, cohortSHA256, package.envelopeSHA256, member.bytesSHA256]),
                  preHeader.inventory.generation == profile.generation,
                  preHeader.inventory.revision >= 0, preHeader.inventory.revision < Int64.max,
                  preHeader.inventory.phase == SharedMediaNativeAppProfile.phase, preHeader.inventory.cursor.isEmpty,
                  preHeader.bootstrapID == profile.inventoryID, preHeader.bootstrapGeneration == profile.generation,
                  preHeader.bootstrapContract == 2, preHeader.bootstrapRevision >= 0,
                  package.id == package.draftID, package.id == member.id,
                  package.ownerID == profile.ownerID, member.ownerID == profile.ownerID,
                  member.inventoryID == profile.inventoryID, member.inventoryGeneration == profile.generation,
                  package.generation == member.draftGeneration, package.contract == PhotoPreparationPolicy.contract,
                  package.tier == "pending", package.phase == "preparedHeld", !package.retiring,
                  package.revision > 0, package.allocated >= 0, package.allocated <= PhotoPreparationPolicy.package,
                  member.revision >= 0, (1...2).contains(targets.count) else { throw SharedMediaStorageFailure.conflict }
            _ = try profile.binding
            let identities = [releaseID, operationID, queueID, observationID, bindingID, generation, eventID]
                + targets.flatMap(\.identities)
            guard Set(identities).count == identities.count else { throw SharedMediaStorageFailure.conflict }
            for target in targets {
                try target.original.validate()
                guard target.original.ownerID == profile.ownerID, target.original.packageID == package.id,
                      target.original.draftGeneration == package.generation,
                      hashes([target.intentSHA256, target.originalIdentitySHA256,
                              target.aiIdentitySHA256, target.displayIdentitySHA256]) else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
    }

    /// A closure assertion, not the physical absence capability itself. Shared
    /// originals retain their allocation/lease/receipt; last references require
    /// the existing stripped acquisition terminal and verified physical absence.
    struct Outcome: Codable, Equatable, Sendable {
        enum Original: String, Codable, Sendable { case shared, removed }
        let pairID: UUID, pairRetirementID: UUID
        let pairClosureSHA256: String
        let original: Original
        let originalRetirementID: UUID?
        let originalClosureSHA256: String

        func validate() throws {
            guard hashes([pairClosureSHA256, originalClosureSHA256]),
                  (original == .shared) == (originalRetirementID == nil),
                  pairRetirementID != originalRetirementID else { throw SharedMediaStorageFailure.conflict }
        }
    }

    struct Released: Codable, Equatable, Sendable {
        enum Format: String, Codable, Sendable { case released = "nativeReceivingReleasedV1" }
        let format: Format
        let plan: Plan
        let releasingSHA256: String
        let inventoryRevision: Int64
        let outcomes: [Outcome]

        init(plan: Plan, inventoryRevision: Int64, outcomes: [Outcome]) throws {
            format = .released; self.plan = plan; self.inventoryRevision = inventoryRevision; self.outcomes = outcomes
            releasingSHA256 = SharedMediaAcquisitionEncoding.digest(try plan.encoded())
            try validate()
        }
        func validate() throws {
            try plan.validate()
            guard releasingSHA256 == SharedMediaAcquisitionEncoding.digest(try plan.encoded()),
                  inventoryRevision > plan.preHeader.inventory.revision,
                  outcomes.map(\.pairID) == plan.targets.map(\.pairID) else { throw SharedMediaStorageFailure.conflict }
            for outcome in outcomes { try outcome.validate() }
            let retirements = outcomes.flatMap { [$0.pairRetirementID] + ($0.originalRetirementID.map { [$0] } ?? []) }
            let originalIDs = Set([plan.releaseID, plan.operationID, plan.queueID, plan.observationID,
                plan.bindingID, plan.generation, plan.eventID] + plan.targets.flatMap(\.identities))
            guard Set(retirements).count == retirements.count,
                  originalIDs.isDisjoint(with: retirements) else { throw SharedMediaStorageFailure.conflict }
        }
        func encoded() throws -> Data {
            try validate(); return try SharedMediaNativeDraftEnvelope.bytes(self)
        }
        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }; return value
        }
    }

    struct SlotBound: Equatable, Sendable {
        let replacedBytes: Int64
        let planBytes: Int64
        let maximumReleasedBytes: Int64
        var charged: Int64 { max(planBytes, maximumReleasedBytes) }
        var reserved: Int64 { charged - planBytes }
    }

    /// Slot-only bound, not a complete cleanup projection. The future owner
    /// must additionally prove every intermediate pair/original/package charge
    /// and revision increment before admitting release.
    static func slotBound(plan: Plan, prepared: Intent.Prepared, received: Intent.Received,
                          acquisitionIDs: [UUID]) throws -> SlotBound {
        try plan.requireMatch(prepared: prepared, received: received, acquisitionIDs: acquisitionIDs)
        let planBytes = Int64(try plan.encoded().count)
        // UUIDs and lowercase SHA-256 values contain no JSON escaping. Removed
        // includes every optional UUID and the longer disposition; Int64.max is
        // the widest supported nonnegative inventory revision. This synthetic
        // sizing value is never decoded, validated as an outcome, or persisted.
        let wide = String(repeating: "a", count: 64)
        let outcomes = plan.targets.map {
            Outcome(pairID: $0.pairID, pairRetirementID: plan.releaseID, pairClosureSHA256: wide,
                original: .removed, originalRetirementID: plan.releaseID, originalClosureSHA256: wide)
        }
        struct Sizing: Encodable {
            let format = Released.Format.released
            let plan: Plan
            let releasingSHA256: String
            let inventoryRevision = Int64.max
            let outcomes: [Outcome]
        }
        let maximum = Int64(try SharedMediaNativeDraftEnvelope.bytes(Sizing(plan: plan,
            releasingSHA256: SharedMediaAcquisitionEncoding.digest(plan.encoded()), outcomes: outcomes)).count)
        let old = try PhotoPreparationPolicy.add([
            Int64(prepared.encoded().count), Int64(received.encoded(prepared: prepared).count)
        ])
        let result = SlotBound(replacedBytes: old, planBytes: planBytes, maximumReleasedBytes: maximum)
        guard planBytes <= PhotoPreparationPolicy.metadata,
              maximum <= PhotoPreparationPolicy.metadata,
              result.charged <= old else { throw SharedMediaStorageFailure.capacity }
        return result
    }

    private static func hashes(_ values: [String]) -> Bool {
        values.allSatisfy(SharedMediaAcquisitionEncoding.isHash)
    }
    private static func digest(_ string: String) -> String {
        SharedMediaAcquisitionEncoding.digest(Data(string.utf8))
    }
}
