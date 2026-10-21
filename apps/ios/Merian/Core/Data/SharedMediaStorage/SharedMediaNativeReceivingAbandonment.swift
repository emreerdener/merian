import Foundation

/// Compact terminal values, not abandonment or restaging authority. The typed
/// owner must still prove result-set absence and seal its exact write set.
extension SharedMediaNativeReceivingIntent {
    struct Abandoned: Codable, Equatable, Sendable {
        enum Format: String, Codable, Sendable {
            case v1 = "nativeReceivingAbandonedV1"
            case v2 = "nativeReceivingAbandonedV2"
        }
        let format: Format
        let version: Int
        let sourceFormat: SharedMediaNativeReceivingIntent.Format
        let profile: SharedMediaNativeAppProfile
        let preparedRevision: Int64
        let revision: Int64
        let preparedSHA256: String
        let operationID: UUID, queueID: UUID, observationID: UUID
        let bindingID: UUID, generation: UUID, eventID: UUID
        let preHeader: SharedMediaNativeAppEligibility.Header
        let package: PackageFence
        let member: MemberFence

        init(prepared: Prepared, header: SharedMediaNativeAppEligibility.Header) throws {
            // Reuse complete prepared/profile/header validation before deriving
            // a terminal value. This does not create an executable request.
            _ = try prepared.descriptorForTransaction(header: header)
            format = prepared.version == 1 ? .v1 : .v2
            version = prepared.version; sourceFormat = prepared.format
            profile = prepared.profile
            preparedRevision = prepared.intentRevision ?? 0
            revision = try SharedMediaStoragePolicy.add(preparedRevision, 1)
            preparedSHA256 = try SharedMediaAcquisitionEncoding.digest(prepared.encoded())
            operationID = prepared.operationID; queueID = prepared.queueID
            observationID = prepared.observationID; bindingID = prepared.bindingID
            generation = prepared.generation; eventID = prepared.eventID
            preHeader = header
            package = PackageFence(try prepared.package.successor(prepared.package.envelope))
            member = MemberFence(prepared.member)
            try validate()
        }

        func encoded() throws -> Data {
            try validate()
            return try SharedMediaNativeDraftEnvelope.bytes(self)
        }

        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
            return value
        }

        /// Strong acknowledgement check. General abandoned-slot audits must
        /// permit later legitimate target edits while retaining this old proof.
        func requireSuccessor(package currentPackage: SharedMediaNativeAppMetadataFacts.Package,
                              member currentMember: SharedMediaNativeAppMetadataFacts.Member) throws {
            try validate()
            guard PackageFence(currentPackage) == package, MemberFence(currentMember) == member else {
                throw SharedMediaStorageFailure.stale
            }
        }

        func validate() throws {
            switch (format, version, sourceFormat, preparedRevision) {
            case (.v1, 1, .prepared, 0): break
            case (.v2, 2, .preparedV2, let value) where value >= 0 && value < Int64.max: break
            default: throw SharedMediaStorageFailure.conflict
            }
            guard revision == (try SharedMediaStoragePolicy.add(preparedRevision, 1)),
                  SharedMediaAcquisitionEncoding.isHash(preparedSHA256),
                  Set([operationID, queueID, observationID, bindingID, generation, eventID]).count == 6,
                  UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
                  SharedMediaAcquisitionEncoding.isHash(profile.physicalBinding),
                  SharedMediaAcquisitionEncoding.isHash(profile.receiptDigest),
                  preHeader.inventory.generation == profile.generation,
                  preHeader.inventory.revision >= 0, preHeader.inventory.revision < Int64.max,
                  preHeader.inventory.phase == SharedMediaNativeAppProfile.phase, preHeader.inventory.cursor.isEmpty,
                  preHeader.bootstrapID == profile.inventoryID, preHeader.bootstrapGeneration == profile.generation,
                  preHeader.bootstrapContract == 2, preHeader.bootstrapRevision >= 0,
                  package.id == package.draftID, package.id == member.id,
                  package.ownerID == profile.ownerID, member.ownerID == profile.ownerID,
                  package.generation == member.draftGeneration,
                  member.inventoryID == profile.inventoryID, member.inventoryGeneration == profile.generation,
                  package.contract == PhotoPreparationPolicy.contract, package.tier == "pending",
                  package.phase == "draftOwned", !package.retiring, package.revision > 0,
                  package.allocated >= 0, package.allocated <= PhotoPreparationPolicy.package,
                  member.revision >= 0, SharedMediaAcquisitionEncoding.isHash(package.envelopeSHA256),
                  SharedMediaAcquisitionEncoding.isHash(member.bytesSHA256) else {
                throw SharedMediaStorageFailure.conflict
            }
            _ = try profile.binding
        }
    }

    /// Every package scalar plus its exact envelope identity. No media or
    /// submitted-description bytes are duplicated in the terminal slot.
    struct PackageFence: Codable, Equatable, Sendable {
        let id: UUID, ownerID: UUID, draftID: UUID, generation: UUID
        let contract: String, tier: String, phase: String
        let revision: Int64, allocated: Int64
        let retiring: Bool
        let envelopeSHA256: String
        init(_ value: SharedMediaNativeAppMetadataFacts.Package) {
            id = value.id; ownerID = value.ownerID; draftID = value.draftID; generation = value.generation
            contract = value.contract; tier = value.tier; phase = value.phase
            revision = value.revision; allocated = value.allocated; retiring = value.retiring
            envelopeSHA256 = SharedMediaAcquisitionEncoding.digest(value.envelope)
        }
    }

    struct MemberFence: Codable, Equatable, Sendable {
        let id: UUID, inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID, draftGeneration: UUID
        let revision: Int64
        let bytesSHA256: String
        init(_ value: SharedMediaNativeAppMetadataFacts.Member) {
            id = value.id; inventoryID = value.inventoryID; inventoryGeneration = value.inventoryGeneration
            ownerID = value.ownerID; draftGeneration = value.draftGeneration; revision = value.revision
            bytesSHA256 = SharedMediaAcquisitionEncoding.digest(value.bytes)
        }
    }
}
