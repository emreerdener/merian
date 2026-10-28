import Foundation

/// Immutable local liability. Neither decoding nor a saved claim grants create,
/// upload, execution, replacement or release authority.
struct SharedMediaNativePhotoAllocation: Codable, Equatable, Sendable {
    static let maximumBytes = Int(PhotoPreparationPolicy.metadata)
    struct Claim: Codable, Equatable, Sendable {
        let profile: SharedMediaNativeAppProfile
        let packageID: UUID, draftGeneration: UUID, operationID: UUID, observationID: UUID, attemptID: UUID
        let preparedSHA256: String, receivedSHA256: String
        let candidateCanonical: String, candidateDigest: String, contentDigest: String

        init(prepared: SharedMediaNativeReceivingIntent.Prepared,
             received: SharedMediaNativeReceivingIntent.Received, attemptID: UUID) throws {
            let candidate = try SharedMediaNativePhotoCandidate(prepared: prepared)
            let content = try SharedMediaNativePhotoContent(prepared: prepared)
            guard let text = String(data: candidate.canonicalBytes, encoding: .utf8) else {
                throw SharedMediaStorageFailure.invalid
            }
            _ = try received.reconstruct(prepared)
            profile = prepared.profile; packageID = prepared.package.id
            draftGeneration = prepared.package.generation; operationID = prepared.operationID
            observationID = prepared.observationID; self.attemptID = attemptID
            preparedSHA256 = SharedMediaAcquisitionEncoding.digest(try prepared.encoded())
            receivedSHA256 = SharedMediaAcquisitionEncoding.digest(try received.encoded(prepared: prepared))
            candidateCanonical = text; candidateDigest = candidate.unverifiedDigest
            contentDigest = content.unverifiedDigest
        }

        func requireMatch(prepared: SharedMediaNativeReceivingIntent.Prepared,
                          received: SharedMediaNativeReceivingIntent.Received) throws {
            guard self == (try Self(prepared: prepared, received: received, attemptID: attemptID)) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    /// Historical assignment evidence only. Original clocks never renew.
    struct Receipt: Codable, Equatable, Sendable {
        let assignmentDigest: String
        let createdAtMilliseconds: Int64, expiresAtMilliseconds: Int64

        func validate() throws {
            guard SharedMediaAcquisitionEncoding.isHash(assignmentDigest),
                  (1...8_639_999_998_200_000).contains(createdAtMilliseconds),
                  expiresAtMilliseconds == createdAtMilliseconds + 1_800_000 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    let version: Int
    let claim: Claim
    let receipt: Receipt?
    var remainingAdvances: Int64 { receipt == nil ? 1 : 0 }

    init(claim: Claim) { version = 1; self.claim = claim; receipt = nil }
    private init(claim: Claim, receipt: Receipt) { version = 1; self.claim = claim; self.receipt = receipt }

    func settling(_ value: Receipt) throws -> Self {
        try value.validate()
        if let receipt {
            guard receipt == value else { throw SharedMediaStorageFailure.conflict }
            return self
        }
        return .init(claim: claim, receipt: value)
    }

    func encoded() throws -> Data {
        guard version == 1, !claim.candidateCanonical.isEmpty,
              claim.candidateCanonical.utf8.count <= 1_048_576,
              [claim.preparedSHA256, claim.receivedSHA256, claim.candidateDigest, claim.contentDigest]
                .allSatisfy(SharedMediaAcquisitionEncoding.isHash) else { throw SharedMediaStorageFailure.conflict }
        try receipt?.validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    static func decode(_ data: Data, sha256: String) throws -> Self {
        guard SharedMediaAcquisitionEncoding.isHash(sha256),
              SharedMediaAcquisitionEncoding.digest(data) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data, maximum: maximumBytes)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    /// Reserve the largest actual canonical successor including JSON escaping,
    /// the receipt key, decimal clocks and the separately stored SHA string.
    var storageCharge: Int64 {
        get throws {
            let current = try encoded().count
            if receipt != nil { return try PhotoPreparationPolicy.add([Int64(current), 64]) }
            let maximum = Receipt(assignmentDigest: String(repeating: "f", count: 64),
                createdAtMilliseconds: 8_639_999_998_200_000, expiresAtMilliseconds: 8_640_000_000_000_000)
            let successor = try settling(maximum).encoded().count
            return try PhotoPreparationPolicy.add([Int64(max(current, successor)), 64])
        }
    }
}
