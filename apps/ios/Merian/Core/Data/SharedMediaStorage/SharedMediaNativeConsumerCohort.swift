import CryptoKit
import Foundation

/// Receiving identity is distinct from the frozen nativeConsumerV2 media codec.
/// Exact bytes survive promotion; this assertion grants no admission or file access.
struct SharedMediaNativeConsumerCohort: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case receiving = "nativeReceivingV1" }
    let format: Format
    let bindingID: UUID
    let originQueueID: String
    let observationID: String
    let executionKind: String
    let inferenceGeneration: UUID?
    let freeze: SharedMediaNativePreparationBlob
    let membership: Data

    func validate() throws {
        try freeze.validate()
        let commit = try SharedMediaNativeFreezeCommit.decode(freeze.bytes)
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
        for field in [Data("merian.shared-photo.native-receiving.v1".utf8), bytes] {
            var length = UInt64(field.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
            hash.update(data: field)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
