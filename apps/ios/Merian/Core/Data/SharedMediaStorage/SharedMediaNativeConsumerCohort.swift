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
        switch format { case .receiving: "native_receiving_v1"; case .intentReceiving: "native_receiving_v2" }
    }
    var queueAuthority: String {
        switch format { case .receiving: "sharedDirectNativeReceivingV1"; case .intentReceiving: "sharedDirectNativeReceivingV2" }
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
