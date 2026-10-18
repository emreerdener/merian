import Foundation

/// Native-only envelope. Historical V1 bytes are read without being rewritten;
/// only explicit preparation may cross the version boundary. Legacy readers
/// continue to reject V2, including an abandoned attempt with no outputs.
enum SharedMediaNativeDraftEnvelope: Sendable {
    case original(PhotoPreparationDraftEnvelope)
    case preparation(V2)

    struct V2: Codable, Sendable {
        let version: Int
        let contexts: [ObservationContext]
        let presentation: [PhotoPreparationImagePresentation]
        let sequence: Int64
        let attempt: SharedMediaNativePreparationBlob?
        let intents: [SharedMediaNativePreparationBlob]
        let frozen: SharedMediaNativePreparationBlob?

        func encoded() throws -> Data {
            guard version == 2, sequence > 0, intents.count <= 2,
                  frozen == nil || attempt == nil else { throw SharedMediaStorageFailure.conflict }
            _ = try PhotoPreparationPolicy.encodeDraft(contexts: contexts, presentation: presentation)
            var sequences = Set<Int64>(), identities = Set<UUID>(), originals = Set<UUID>(), slots = Set<Int64>()
            if let attempt {
                try attempt.validate()
                let request = try SharedMediaNativePreparationAttempt.decode(attempt.bytes)
                guard request.sequence == sequence else { throw SharedMediaStorageFailure.conflict }
                sequences.insert(request.sequence)
                originals.insert(request.original.reference.referenceID); slots.insert(request.original.ordinal)
            }
            for blob in intents {
                try blob.validate()
                let value = try SharedMediaNativeDerivativeIntent.decode(blob.bytes), request = try value.attempt()
                guard request.sequence <= sequence, sequences.insert(request.sequence).inserted,
                      originals.insert(request.original.reference.referenceID).inserted,
                      slots.insert(request.original.ordinal).inserted else { throw SharedMediaStorageFailure.conflict }
                for id in [value.pairID, value.nonce, value.ai.id, value.display.id, value.ai.assetID, value.display.assetID,
                           value.ai.referenceID, value.display.referenceID, value.ai.leaseID, value.display.leaseID] {
                    guard identities.insert(id).inserted else { throw SharedMediaStorageFailure.conflict }
                }
            }
            guard originals.count <= 2 else { throw SharedMediaStorageFailure.conflict }
            if let frozen {
                try frozen.validate()
                try SharedMediaNativeFreezeCommit.validateHistoricalOrCurrent(frozen.bytes)
            }
            return try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata))
        }
        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
            return value
        }
    }

    static func decode(_ bytes: Data) throws -> Self {
        struct Version: Decodable { let version: Int }
        let header: Version = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        switch header.version {
        case 1: return .original(try PhotoPreparationPolicy.decodeDraft(bytes))
        case 2: return .preparation(try V2.decode(bytes))
        default: throw SharedMediaStorageFailure.conflict
        }
    }
    var contexts: [ObservationContext] {
        switch self {
        case .original(let value): value.contexts
        case .preparation(let value): value.contexts
        }
    }
    var presentation: [PhotoPreparationImagePresentation] {
        switch self {
        case .original(let value): value.presentation
        case .preparation(let value): value.presentation
        }
    }
    var sequence: Int64 { if case .preparation(let value) = self { return value.sequence }; return 0 }
    var attempt: SharedMediaNativePreparationBlob? { if case .preparation(let value) = self { return value.attempt }; return nil }
    var intents: [SharedMediaNativePreparationBlob] { if case .preparation(let value) = self { return value.intents }; return [] }

    /// Metadata cannot introduce, change or remove lifecycle authority.
    func editing(contexts: [ObservationContext], presentation: [PhotoPreparationImagePresentation]) throws -> Data {
        switch self {
        case .original: return try PhotoPreparationPolicy.encodeDraft(contexts: contexts, presentation: presentation)
        case .preparation(let value):
            guard value.attempt == nil, value.frozen == nil else { throw SharedMediaStorageFailure.closed }
            // Until the pair owner handles explicit replacement, presentation
            // of prepared originals cannot change through a metadata save.
            let preparedIDs = try Set(value.intents.map { try SharedMediaNativeDerivativeIntent.decode($0.bytes).attempt().original.reference.referenceID })
            let before = value.presentation.filter { preparedIDs.contains($0.referenceID) }
            let after = presentation.filter { preparedIDs.contains($0.referenceID) }
            guard try Self.bytes(before) == Self.bytes(after) else { throw SharedMediaStorageFailure.closed }
            return try V2(version: 2, contexts: contexts, presentation: presentation, sequence: value.sequence,
                attempt: nil, intents: value.intents, frozen: nil).encoded()
        }
    }
    func validateMetadataTransition(to bytes: Data) throws {
        let next = try Self.decode(bytes)
        switch (self, next) {
        case (.original, .original): break
        case (.preparation, .preparation):
            guard try editing(contexts: next.contexts, presentation: next.presentation) == bytes else { throw SharedMediaStorageFailure.conflict }
        default: throw SharedMediaStorageFailure.conflict
        }
    }
    static func bytes<T: Encodable>(_ value: T) throws -> Data {
        try SharedMediaAcquisitionEncoding.encode(value, maximum: Int(PhotoPreparationPolicy.metadata))
    }
}

/// Frozen supporting content excludes lifecycle and digest fields. Its exact
/// canonical bytes are retained by the receiving consumer.
struct SharedMediaNativeFrozenSupporting: Codable, Sendable {
    let contexts: [ObservationContext]
    let presentation: [PhotoPreparationImagePresentation]
    func encoded() throws -> Data {
        _ = try PhotoPreparationPolicy.encodeDraft(contexts: contexts, presentation: presentation)
        return try SharedMediaNativeDraftEnvelope.bytes(self)
    }
}

struct SharedMediaNativeFrozenEntry: Codable, Equatable, Sendable {
    let position: Int
    let intent: SharedMediaNativePreparationBlob
    let aiReferenceRevision: Int64
    let displayReferenceRevision: Int64
    let aiDescriptor: SharedMediaPhotoRetirementIdentity
    let displayDescriptor: SharedMediaPhotoRetirementIdentity
}

struct SharedMediaNativeFrozenCohort: Codable, Sendable {
    enum Format: String, Codable, Sendable { case cohort = "nativeConsumerV2" }
    let format: Format
    let packageID: UUID
    let ownerID: UUID
    let draftGeneration: UUID
    let supportingBytes: Data
    let entries: [SharedMediaNativeFrozenEntry]

    func encoded() throws -> Data {
        guard (1...2).contains(entries.count), entries.map(\.position) == Array(0..<entries.count) else { throw SharedMediaStorageFailure.conflict }
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try supporting.encoded() == supportingBytes else { throw SharedMediaStorageFailure.conflict }
        var references = Set<UUID>(), slots = Set<Int64>(), pairs = Set<UUID>()
        for entry in entries {
            try entry.intent.validate()
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes), attempt = try intent.attempt()
            let original = attempt.original.reference
            guard original.packageID == packageID, original.ownerID == ownerID, original.draftGeneration == draftGeneration,
                  references.insert(original.referenceID).inserted, slots.insert(attempt.original.ordinal).inserted,
                  pairs.insert(intent.pairID).inserted, entry.aiReferenceRevision >= 0, entry.displayReferenceRevision >= 0 else { throw SharedMediaStorageFailure.conflict }
            _ = try SharedMediaPhotoRetirementIdentity.decode(entry.aiDescriptor.encoded())
            _ = try SharedMediaPhotoRetirementIdentity.decode(entry.displayDescriptor.encoded())
        }
        guard supporting.presentation.allSatisfy({ references.contains($0.referenceID) }) else { throw SharedMediaStorageFailure.conflict }
        return try SharedMediaNativeDraftEnvelope.bytes(self)
    }
    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }; return value
    }
}

struct SharedMediaNativeFreezeReceipt: Codable, Sendable {
    enum Format: String, Codable, Sendable { case receipt = "nativeFreezeV2" }
    let format: Format
    let operationID: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let inventoryRevision: Int64
    let packageRevision: Int64
    let membershipRevision: Int64
    let cohort: SharedMediaNativePreparationBlob
    func encoded() throws -> Data {
        guard [inventoryRevision, packageRevision, membershipRevision].allSatisfy({ $0 >= 0 }) else { throw SharedMediaStorageFailure.conflict }
        try cohort.validate(); _ = try SharedMediaNativeFrozenCohort.decode(cohort.bytes)
        return try SharedMediaNativeDraftEnvelope.bytes(self)
    }
    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }; return value
    }
}
