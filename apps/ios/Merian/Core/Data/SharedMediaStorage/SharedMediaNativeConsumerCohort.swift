import CryptoKit
import Foundation

/// Receiving identity is distinct from the frozen nativeConsumerV2 media codec.
/// Exact bytes survive promotion; this assertion grants no admission or file access.
struct SharedMediaNativeConsumerCohort: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable {
        case receiving = "nativeReceivingV1"
        case intentReceiving = "nativeIntentReceivingV2"
    }
    struct IntentBinding: Codable, Equatable, Sendable {
        let packageID: UUID
        let operationID: UUID
        let preparedRevision: Int64
        let preparedSHA256: String
        let restagedFromSHA256: String?
        let photoAdmission: SharedMediaNativePhotoAdmission?
        init(packageID: UUID, operationID: UUID, preparedRevision: Int64, preparedSHA256: String,
             restagedFromSHA256: String? = nil, photoAdmission: SharedMediaNativePhotoAdmission? = nil) {
            self.packageID = packageID; self.operationID = operationID
            self.preparedRevision = preparedRevision; self.preparedSHA256 = preparedSHA256
            self.restagedFromSHA256 = restagedFromSHA256; self.photoAdmission = photoAdmission
        }
    }
    let format: Format
    let bindingID: UUID
    let originQueueID: String
    let observationID: String
    let executionKind: String
    let inferenceGeneration: UUID?
    let freeze: SharedMediaNativePreparationBlob
    let membership: Data
    let intentBinding: IntentBinding?

    init(format: Format, bindingID: UUID, originQueueID: String, observationID: String,
         executionKind: String, inferenceGeneration: UUID?, freeze: SharedMediaNativePreparationBlob,
         membership: Data, intentBinding: IntentBinding? = nil) {
        self.format = format; self.bindingID = bindingID; self.originQueueID = originQueueID
        self.observationID = observationID; self.executionKind = executionKind
        self.inferenceGeneration = inferenceGeneration; self.freeze = freeze
        self.membership = membership; self.intentBinding = intentBinding
    }

    var metadataKey: String {
        switch format {
        case .receiving: "native_receiving_v1"
        case .intentReceiving: "native_receiving_v2"
        }
    }
    var queueAuthority: String {
        switch format {
        case .receiving: "sharedDirectNativeReceivingV1"
        case .intentReceiving: "sharedDirectNativeReceivingV2"
        }
    }

    func validate() throws {
        try freeze.validate()
        let commit = try SharedMediaNativeFreezeCommit.decode(freeze.bytes)
        switch (format, intentBinding) {
        case (.receiving, nil): break
        case (.intentReceiving, .some(let binding)):
            try binding.photoAdmission?.validate()
            let media = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
            if let predecessor = binding.restagedFromSHA256 {
                guard binding.preparedRevision > 0, SharedMediaAcquisitionEncoding.isHash(predecessor) else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            guard binding.packageID == media.packageID, binding.operationID == commit.operationID,
                  binding.preparedRevision >= 0, binding.preparedRevision < Int64.max,
                  SharedMediaAcquisitionEncoding.isHash(binding.preparedSHA256),
                  executionKind == "ordinaryV1", inferenceGeneration != nil else {
                throw SharedMediaStorageFailure.conflict
            }
        default: throw SharedMediaStorageFailure.conflict
        }
        _ = try SharedMediaMembership.decode(membership)
        _ = try SharedMediaConsumerExecution.classify(raw: executionKind, generation: inferenceGeneration)
        guard [originQueueID, observationID].allSatisfy({ value in
            UUID(uuidString: value)?.uuidString.lowercased() == value
        }), SharedMediaAcquisitionEncoding.digest(membership) == commit.membershipSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
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

    func digest() throws -> String {
        let bytes = try encoded()
        var hash = SHA256()
        let domain = format == .receiving ? "merian.shared-photo.native-receiving.v1" : "merian.shared-photo.native-intent-receiving.v2"
        for field in [Data(domain.utf8), bytes] {
            var length = UInt64(field.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
            hash.update(data: field)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// Kept with the consumer codec owner. These values grant no reservation,
// application, file access or replay authority.
extension SharedMediaNativeConsumerCohort {
    enum AppliedInitialFormat: String, Codable, Sendable {
        case initial = "nativeInitialAppliedV1"
        case history = "nativeInitialHistoryV1"
    }

    /// A separate closed envelope: old receiving decoders still reject it.
    /// The original receiving assertion is immutable historical evidence.
    struct AppliedInitial: Codable, Equatable, Sendable {
        let format: AppliedInitialFormat
        let original: SharedMediaNativeConsumerCohort
        let receipt: InitialApplicationReceipt
        /// One future native acknowledgement binds the saved V3 baseline.
        /// It is not enrollment's own save or a media-ownership transfer.
        let historyHandoffRemainingAdvances: Int64
        let historyBaseline: NativeHistoryAssociation?
        var consumerRevision: Int64 { format == .initial ? 1 : 2 }

        init(original: SharedMediaNativeConsumerCohort, receipt: InitialApplicationReceipt) throws {
            format = .initial; self.original = original; self.receipt = receipt; historyHandoffRemainingAdvances = 1
            historyBaseline = nil
            _ = try encoded()
        }

        init(acknowledging before: Self, association: NativeHistoryAssociation) throws {
            guard before.format == .initial else { throw SharedMediaStorageFailure.conflict }
            _ = try before.encoded()
            format = .history; original = before.original; receipt = before.receipt
            historyHandoffRemainingAdvances = 0; historyBaseline = association
            _ = try encoded()
        }

        func encoded() throws -> Data {
            switch format {
            case .initial:
                guard historyHandoffRemainingAdvances == 1, historyBaseline == nil else { throw SharedMediaStorageFailure.conflict }
            case .history:
                guard historyHandoffRemainingAdvances == 0, let historyBaseline,
                      historyBaseline.ownerID == receipt.ownerID, historyBaseline.observationID == receipt.observationID else {
                    throw SharedMediaStorageFailure.conflict
                }
                try historyBaseline.validate()
            }
            try original.validate()
            _ = try receipt.encoded()
            let commit = try SharedMediaNativeFreezeCommit.decode(original.freeze.bytes)
            let media = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
            guard original.format == .intentReceiving, let binding = original.intentBinding,
                  receipt.inventoryID == commit.inventoryID, receipt.inventoryGeneration == commit.inventoryGeneration,
                  receipt.ownerID == media.ownerID, receipt.packageID == media.packageID,
                  receipt.draftGeneration == media.draftGeneration, receipt.operationID == commit.operationID,
                  receipt.operationID == binding.operationID, receipt.bindingID == original.bindingID,
                  receipt.queueID.uuidString.lowercased() == original.originQueueID,
                  receipt.observationID.uuidString.lowercased() == original.observationID,
                  receipt.inferenceGeneration == original.inferenceGeneration else { throw SharedMediaStorageFailure.conflict }
            return try SharedMediaNativeDraftEnvelope.bytes(self)
        }

        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
            return value
        }

        func digest() throws -> String {
            var hash = SHA256()
            let domain = format == .initial ? "merian.shared-photo.native-initial-applied.v1" : "merian.shared-photo.native-initial-history.v1"
            for field in [Data(domain.utf8), try encoded()] {
                var length = UInt64(field.count).bigEndian
                withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
                hash.update(data: field)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    enum InitialApplicationFormat: String, Codable, Sendable {
        case initial = "nativeInitialApplicationV1"
        case presentation = "nativeInitialApplicationV2"
    }
    struct InitialApplicationReceipt: Codable, Equatable, Sendable {
        static let maximumBytes = 4096
        static let maximumBaselineBytes = 1_048_576
        let format: InitialApplicationFormat
        let inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID
        let packageID: UUID, draftGeneration: UUID, operationID: UUID
        let bindingID: UUID, queueID: UUID, observationID: UUID, inferenceGeneration: UUID
        let originalRowSHA256: String, completionSHA256: String, referenceSHA256: String
        let resultDigest: String, provenanceDigest: String
        let baselineSHA256: String
        let baselineByteCount: Int
        let presentationSHA256: String?
        let presentationByteCount: Int?

        /// The baseline is a bounded historical projection, never a demand that
        /// a later edited scan still equal its initial result. The future writer
        /// must independently construct and seal it before any atomic save.
        @MainActor
        init(snapshot: SharedMediaNativePhotoAllocationSnapshot, row: SharedMediaReceivingIntentRecord,
             acquisition: InitialCompletionDocuments.CpmAcquisition, baseline: Data) throws {
            guard snapshot.row == SharedMediaNativeReceivingIntentGraph.Row(row),
                  snapshot.initialPin?.completion == acquisition.record,
                  !baseline.isEmpty, baseline.count <= Self.maximumBaselineBytes else {
                throw SharedMediaStorageFailure.conflict
            }
            let prepared = snapshot.prepared
            let reference = try InitialAnalysisCanonical.parse(acquisition.result.reference).object
            guard reference?["owner_id"]?.string == prepared.profile.ownerID.uuidString.lowercased(),
                  reference?["scan_id"]?.string == prepared.observationID.uuidString.lowercased() else {
                throw SharedMediaStorageFailure.conflict
            }
            try snapshot.requireSettledPresentation()
            format = .presentation
            presentationSHA256 = Self.presentationDigest(snapshot.recoveryPresentationData)
            presentationByteCount = snapshot.recoveryPresentationData?.count ?? 0
            inventoryID = prepared.profile.inventoryID; inventoryGeneration = prepared.profile.generation
            ownerID = prepared.profile.ownerID; packageID = prepared.package.id; draftGeneration = prepared.package.generation
            operationID = prepared.operationID; bindingID = prepared.bindingID; queueID = prepared.queueID
            observationID = prepared.observationID; inferenceGeneration = prepared.generation
            originalRowSHA256 = try Self.originalDigest(row)
            completionSHA256 = SharedMediaAcquisitionEncoding.digest(acquisition.record.bytes)
            referenceSHA256 = SharedMediaAcquisitionEncoding.digest(acquisition.result.reference)
            resultDigest = acquisition.result.resultDigest; provenanceDigest = acquisition.result.provenanceDigest
            baselineSHA256 = Self.digest(domain: "baseline", fields: [("bytes", baseline)])
            baselineByteCount = baseline.count
            _ = try encoded()
        }

        func encoded() throws -> Data {
            guard (1...Self.maximumBaselineBytes).contains(baselineByteCount),
                  [originalRowSHA256, completionSHA256, referenceSHA256, resultDigest, provenanceDigest, baselineSHA256]
                    .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.invalid }
            switch format {
            case .initial:
                guard presentationSHA256 == nil, presentationByteCount == nil else { throw SharedMediaStorageFailure.invalid }
            case .presentation:
                guard let hash = presentationSHA256, SharedMediaAcquisitionEncoding.isHash(hash),
                      let count = presentationByteCount, (0...AnalysisRecoveryPresentation.maximumBytes).contains(count),
                      count != 0 || hash == Self.presentationDigest(nil) else { throw SharedMediaStorageFailure.invalid }
            }
            return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
        }
        static func decode(_ bytes: Data) throws -> Self {
            let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: maximumBytes)
            guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
            return value
        }

        func requirePresentation(_ bytes: Data?) throws {
            switch format {
            case .initial:
                guard bytes == nil else { throw SharedMediaStorageFailure.conflict }
            case .presentation:
                guard presentationByteCount == (bytes?.count ?? 0),
                      presentationSHA256 == Self.presentationDigest(bytes) else { throw SharedMediaStorageFailure.conflict }
            }
        }

        private static func presentationDigest(_ bytes: Data?) -> String {
            digest(domain: "presentation", fields: [("present", Data([bytes == nil ? 0 : 1])), ("bytes", bytes ?? Data())])
        }

        func requireBaseline(_ bytes: Data) throws {
            guard bytes.count == baselineByteCount,
                  Self.digest(domain: "baseline", fields: [("bytes", bytes)]) == baselineSHA256 else { throw SharedMediaStorageFailure.conflict }
        }

        /// Hash every persisted scalar and optional byte field, including nils.
        /// Existing raw-field ownership makes additions explicit. A commitment
        /// binds bytes but never substitutes for the typed original row checks.
        @MainActor
        static func originalDigest(_ row: SharedMediaReceivingIntentRecord) throws -> String {
            guard row.cursorKey.utf8.count <= 36, row.phaseRaw.utf8.count <= 32,
                  [row.preparedSHA256, row.resultSHA256, row.releaseStartSHA256, row.allocationSHA256,
                   row.initialAdmissionSHA256, row.initialCompletionSHA256].allSatisfy({ ($0?.utf8.count ?? 0) <= 64 }) else {
                throw SharedMediaStorageFailure.capacity
            }
            let blobs = [row.preparedData, row.resultData, row.releaseStartData, row.allocationData,
                         row.initialAdmissionData, row.initialCompletionData]
            guard try PhotoPreparationPolicy.add(blobs.compactMap { $0.map { Int64($0.count) } }) <= PhotoPreparationPolicy.metadata else {
                throw SharedMediaStorageFailure.capacity
            }
            let fields = try SharedMediaNativeReleasePairRaw.fields(row)
            return digest(domain: "original-row", fields: fields.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        }
        private static func digest(domain: String, fields: [(String, Data)]) -> String {
            var hash = SHA256()
            func include(_ bytes: Data) {
                var length = UInt64(bytes.count).bigEndian
                withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
                hash.update(data: bytes)
            }
            include(Data("merian.shared-photo.initial-application.\(domain).v1".utf8))
            for (key, bytes) in fields { include(Data(key.utf8)); include(bytes) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}
