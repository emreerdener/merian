import Foundation

/// Canonical persistence values only. Neither an intent nor a reconstructed
/// receipt grants a save, file, account, network, or execution capability.
enum SharedMediaNativeReceivingIntent {
    enum Format: String, Codable, Sendable {
        case prepared = "nativeReceivingIntentV1"
        case received = "nativeReceivingResultV1"
        case preparedV2 = "nativeReceivingIntentV2"
        case receivedV2 = "nativeReceivingResultV2"
    }
    struct Prepared: Codable, Sendable {
        let format: Format
        let version: Int
        let profile: SharedMediaNativeAppProfile
        let package: SharedMediaNativeAppMetadataFacts.Package
        let member: SharedMediaNativeAppMetadataFacts.Member
        let cohort: SharedMediaNativePreparationBlob
        let operationID: UUID, queueID: UUID, observationID: UUID
        let bindingID: UUID, generation: UUID, eventID: UUID
        let timestampBits: UInt64
        let intentRevision: Int64?
        let restagedFromSHA256: String?
        let photoAdmission: SharedMediaNativePhotoAdmission?

        init(_ request: SharedMediaNativeAppReceivingRequest) throws { try self.init(Transaction(request)) }
        init(_ request: Transaction) throws {
            guard let queue = UUID(uuidString: request.cohort.originQueueID),
                  let observation = UUID(uuidString: request.cohort.observationID),
                  let event = UUID(uuidString: request.eventID),
                  let generation = request.cohort.inferenceGeneration else { throw SharedMediaStorageFailure.invalid }
            try self.init(profile: request.profile, package: request.package, member: request.member,
                cohort: request.freeze.commit.cohort, operationID: request.freeze.commit.operationID,
                queueID: queue, observationID: observation, bindingID: request.cohort.bindingID,
                generation: generation, eventID: event, timestamp: request.timestamp,
                intentRevision: request.cohort.intentBinding?.preparedRevision,
                restagedFromSHA256: request.cohort.intentBinding?.restagedFromSHA256,
                photoAdmission: request.cohort.intentBinding?.photoAdmission)
            let rebuilt = try descriptorForTransaction(header: request.header)
            guard try canonicalRequest(rebuilt) == canonicalRequest(request) else { throw SharedMediaStorageFailure.conflict }
        }
        init(profile: SharedMediaNativeAppProfile, package: SharedMediaNativeAppMetadataFacts.Package,
             member: SharedMediaNativeAppMetadataFacts.Member, cohort: SharedMediaNativePreparationBlob,
             operationID: UUID, queueID: UUID, observationID: UUID, bindingID: UUID, generation: UUID,
             eventID: UUID, timestamp: Date, intentRevision: Int64? = nil, restagedFromSHA256: String? = nil,
             photoAdmission: SharedMediaNativePhotoAdmission? = nil) throws {
            format = intentRevision == nil ? .prepared : .preparedV2
            version = intentRevision == nil ? 1 : 2
            self.intentRevision = intentRevision; self.restagedFromSHA256 = restagedFromSHA256
            self.photoAdmission = photoAdmission
            self.profile = profile; self.package = package; self.member = member
            self.cohort = cohort; self.operationID = operationID; self.queueID = queueID
            self.observationID = observationID; self.bindingID = bindingID; self.generation = generation
            self.eventID = eventID; timestampBits = timestamp.timeIntervalSinceReferenceDate.bitPattern
            try validate()
        }
        func requireSelection(draftGeneration: UUID, pairIDs: [UUID]) throws {
            let frozen = try SharedMediaNativeFrozenCohort.decode(cohort.bytes)
            guard package.generation == draftGeneration,
                  try frozen.entries.map({ try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID }) == pairIDs else {
                throw SharedMediaStorageFailure.stale
            }
        }
        func encoded() throws -> Data {
            try validate(); return try SharedMediaNativeDraftEnvelope.bytes(self)
        }
        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }; return value
        }
        func descriptorForTransaction(header: SharedMediaNativeAppEligibility.Header) throws -> Transaction {
            try validate()
            guard header.inventory.generation == profile.generation, header.inventory.revision >= 0,
                  header.inventory.revision < Int64.max, header.inventory.phase == SharedMediaNativeAppProfile.phase,
                  header.inventory.cursor.isEmpty, header.bootstrapID == profile.inventoryID,
                  header.bootstrapGeneration == profile.generation, header.bootstrapContract == 2,
                  header.bootstrapRevision >= 0 else { throw SharedMediaStorageFailure.conflict }
            let commit = SharedMediaNativeFreezeCommit(format: .receipt, operationID: operationID,
                inventoryID: profile.inventoryID, inventoryGeneration: profile.generation,
                beforeInventoryRevision: header.inventory.revision, beforePackageRevision: package.revision,
                membershipRevision: member.revision,
                previousEnvelopeSHA256: SharedMediaAcquisitionEncoding.digest(package.envelope),
                membershipSHA256: SharedMediaAcquisitionEncoding.digest(member.bytes), cohort: cohort)
            let freeze = SharedMediaNativeFreezeRequest(commit: commit, previousEnvelope: package.envelope, membership: member.bytes)
            try freeze.validate()
            let binding = try intentRevision.map {
                SharedMediaNativeConsumerCohort.IntentBinding(packageID: package.id, operationID: operationID,
                    preparedRevision: $0, preparedSHA256: SharedMediaAcquisitionEncoding.digest(try encoded()),
                    restagedFromSHA256: restagedFromSHA256, photoAdmission: photoAdmission)
            }
            return try .init(profile: profile, header: header, package: package, member: member, freeze: freeze,
                queueID: queueID, observationID: observationID, bindingID: bindingID, generation: generation,
                eventID: eventID, timestamp: Date(timeIntervalSinceReferenceDate: Double(bitPattern: timestampBits)),
                intentBinding: binding)
        }
        private func validate() throws {
            let interval = Double(bitPattern: timestampBits)
            switch (format, version, intentRevision) {
            case (.prepared, 1, nil): break
            case (.preparedV2, 2, .some(let revision)) where revision >= 0 && revision < Int64.max: break
            default: throw SharedMediaStorageFailure.conflict
            }
            if let photoAdmission {
                guard version == 2 else { throw SharedMediaStorageFailure.conflict }
                try photoAdmission.validate()
            }
            if let predecessor = restagedFromSHA256 {
                guard version == 2, let intentRevision, intentRevision > 0,
                      SharedMediaAcquisitionEncoding.isHash(predecessor) else { throw SharedMediaStorageFailure.conflict }
            }
            guard interval.isFinite,
                  Date(timeIntervalSinceReferenceDate: interval).timeIntervalSinceReferenceDate.bitPattern == timestampBits,
                  package.draftID == package.id, package.id == member.id, package.ownerID == profile.ownerID, member.ownerID == profile.ownerID,
                  package.generation == member.draftGeneration, member.inventoryID == profile.inventoryID,
                  member.inventoryGeneration == profile.generation, package.revision >= 0, package.revision < Int64.max,
                  member.revision >= 0, package.allocated >= 0, package.contract == PhotoPreparationPolicy.contract,
                  package.tier == "pending", package.phase == "draftOwned", !package.retiring,
                  Set([operationID, queueID, observationID, bindingID, generation, eventID]).count == 6 else {
                throw SharedMediaStorageFailure.conflict
            }
            guard UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
                  SharedMediaAcquisitionEncoding.isHash(profile.physicalBinding),
                  SharedMediaAcquisitionEncoding.isHash(profile.receiptDigest) else { throw SharedMediaStorageFailure.conflict }
            _ = try profile.binding
            _ = try SharedMediaMembership.decode(member.bytes)
            try cohort.validate()
            let frozen = try SharedMediaNativeFrozenCohort.decode(cohort.bytes)
            guard frozen.packageID == package.id, frozen.ownerID == profile.ownerID,
                  frozen.draftGeneration == package.generation,
                  case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.envelope),
                  envelope.attempt == nil, envelope.frozen == nil,
                  frozen.entries.count == envelope.intents.count,
                  Set(frozen.entries.map { $0.intent.bytes }) == Set(envelope.intents.map(\.bytes)),
                  frozen.supportingBytes == (try SharedMediaNativeFrozenSupporting(contexts: envelope.contexts,
                    presentation: envelope.presentation).encoded()) else { throw SharedMediaStorageFailure.conflict }
        }
    }

    struct Received: Codable, Sendable {
        let format: Format
        let version: Int
        let preHeader: SharedMediaNativeAppEligibility.Header
        let preparedSHA256: String
        let requestSHA256: String
        init(prepared: Prepared, request: SharedMediaNativeAppReceivingRequest) throws {
            try self.init(prepared: prepared, request: Transaction(request))
        }
        init(prepared: Prepared, request: Transaction) throws {
            format = prepared.version == 1 ? .received : .receivedV2
            version = prepared.version; preHeader = request.header
            preparedSHA256 = try SharedMediaAcquisitionEncoding.digest(prepared.encoded())
            let reconstructed = try prepared.descriptorForTransaction(header: preHeader)
            let bytes = try canonicalRequest(reconstructed)
            guard bytes == (try canonicalRequest(request)) else { throw SharedMediaStorageFailure.conflict }
            requestSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
        }
        func reconstruct(_ prepared: Prepared) throws -> Transaction {
            guard format == (prepared.version == 1 ? .received : .receivedV2),
                  version == prepared.version, SharedMediaAcquisitionEncoding.isHash(preparedSHA256),
                  SharedMediaAcquisitionEncoding.isHash(requestSHA256),
                  preparedSHA256 == (try SharedMediaAcquisitionEncoding.digest(prepared.encoded())) else {
                throw SharedMediaStorageFailure.conflict
            }
            let request = try prepared.descriptorForTransaction(header: preHeader)
            guard requestSHA256 == (try SharedMediaAcquisitionEncoding.digest(canonicalRequest(request))) else {
                throw SharedMediaStorageFailure.conflict
            }
            return request
        }
        func encoded(prepared: Prepared) throws -> Data {
            _ = try reconstruct(prepared); return try SharedMediaNativeDraftEnvelope.bytes(self)
        }
        static func decode(_ bytes: Data, prepared: Prepared) throws -> Self {
            let result: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try result.encoded(prepared: prepared) == bytes else { throw SharedMediaStorageFailure.conflict }; return result
        }
    }
    /// A descriptive value, deliberately not SharedMediaNativeAppReceivingRequest.
    /// Conversion to a request grants no authority. The receiving owner must
    /// validate the exact persisted slot and cohort before any fresh mutation.
    struct Transaction: Sendable {
        let profile: SharedMediaNativeAppProfile
        let header: SharedMediaNativeAppEligibility.Header
        let package: SharedMediaNativeAppMetadataFacts.Package
        let member: SharedMediaNativeAppMetadataFacts.Member
        let freeze: SharedMediaNativeFreezeRequest
        let cohort: SharedMediaNativeConsumerCohort
        let timestamp: Date
        let eventID: String, metadata: String
        var jobID: String { "scan-ingestion:" + cohort.originQueueID }
        init(_ request: SharedMediaNativeAppReceivingRequest) {
            profile = request.profile; header = request.header; package = request.package; member = request.member
            freeze = request.freeze; cohort = request.cohort; timestamp = request.timestamp
            eventID = request.eventID; metadata = request.metadata
        }
        fileprivate init(profile: SharedMediaNativeAppProfile, header: SharedMediaNativeAppEligibility.Header,
                         package: SharedMediaNativeAppMetadataFacts.Package, member: SharedMediaNativeAppMetadataFacts.Member,
                         freeze: SharedMediaNativeFreezeRequest, queueID: UUID, observationID: UUID, bindingID: UUID,
                         generation: UUID, eventID: UUID, timestamp: Date,
                         intentBinding: SharedMediaNativeConsumerCohort.IntentBinding?) throws {
            self.profile = profile; self.header = header; self.package = package; self.member = member; self.freeze = freeze
            cohort = .init(format: intentBinding == nil ? .receiving : .intentReceiving,
                bindingID: bindingID, originQueueID: queueID.uuidString.lowercased(),
                observationID: observationID.uuidString.lowercased(), executionKind: "ordinaryV1", inferenceGeneration: generation,
                freeze: .init(bytes: try freeze.commit.encoded()), membership: member.bytes, intentBinding: intentBinding)
            self.timestamp = timestamp; self.eventID = eventID.uuidString.lowercased()
            let bytes = try SharedMediaNativeDraftEnvelope.bytes([
                cohort.metadataKey: try cohort.digest(), "inference_generation": generation.uuidString.lowercased(),
                "operation_id": freeze.commit.operationID.uuidString.lowercased(), "event_id": self.eventID])
            guard timestamp.timeIntervalSince1970.isFinite, let json = String(data: bytes, encoding: .utf8) else {
                throw SharedMediaStorageFailure.conflict
            }
            metadata = json
        }
        func frozenPackage() throws -> SharedMediaNativeAppMetadataFacts.Package {
            guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(freeze.previousEnvelope) else {
                throw SharedMediaStorageFailure.conflict
            }
            let bytes = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: value.contexts, presentation: value.presentation,
                sequence: value.sequence, attempt: nil, intents: value.intents, frozen: cohort.freeze).encoded()
            return try package.successor(bytes, phase: "preparedHeld")
        }
    }
    private struct RequestBytes: Encodable {
        let profile: SharedMediaNativeAppProfile
        let header: SharedMediaNativeAppEligibility.Header
        let package: SharedMediaNativeAppMetadataFacts.Package
        let member: SharedMediaNativeAppMetadataFacts.Member
        let freeze: SharedMediaNativeFreezeRequest
        let cohort: SharedMediaNativeConsumerCohort
        let timestampBits: UInt64
        let eventID: String, metadata: String
    }
    static func canonicalRequest(_ request: SharedMediaNativeAppReceivingRequest) throws -> Data {
        try canonicalRequest(Transaction(request))
    }
    static func canonicalRequest(_ request: Transaction) throws -> Data {
        try SharedMediaNativeDraftEnvelope.bytes(RequestBytes(profile: request.profile, header: request.header,
            package: request.package, member: request.member, freeze: request.freeze, cohort: request.cohort,
            timestampBits: request.timestamp.timeIntervalSinceReferenceDate.bitPattern, eventID: request.eventID,
            metadata: request.metadata))
    }
}

/// A descriptive request reconstructed from versioned immutable values.
/// Only the receiving owner can admit a saved P2 slot; this grants no authority.
struct SharedMediaNativeAppReceivingRequest: Sendable {
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    let package: SharedMediaNativeAppMetadataFacts.Package
    let member: SharedMediaNativeAppMetadataFacts.Member
    let freeze: SharedMediaNativeFreezeRequest
    let cohort: SharedMediaNativeConsumerCohort
    let timestamp: Date
    let eventID: String
    let metadata: String
    var jobID: String { "scan-ingestion:" + cohort.originQueueID }
    init(_ transaction: SharedMediaNativeReceivingIntent.Transaction) {
        profile = transaction.profile; header = transaction.header; package = transaction.package
        member = transaction.member; freeze = transaction.freeze; cohort = transaction.cohort
        timestamp = transaction.timestamp; eventID = transaction.eventID; metadata = transaction.metadata
    }
    func frozenPackage() throws -> SharedMediaNativeAppMetadataFacts.Package {
        try SharedMediaNativeReceivingIntent.Transaction(self).frozenPackage()
    }
}
