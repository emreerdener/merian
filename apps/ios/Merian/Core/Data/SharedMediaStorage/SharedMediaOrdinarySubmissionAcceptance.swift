import Foundation

/// Historical complete-set save receipt. It cannot establish that a save
/// committed, qualify current ownership or grant file access by itself.
struct SharedMediaOrdinarySubmissionAcceptance: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "ordinaryPhotoSubmissionAcceptanceV1" }
    struct Member: Codable, Equatable, Sendable {
        let holdID: UUID
        let acceptanceSHA256: String
    }
    let format: Format
    let requestSHA256: String
    let inventoryRevision: Int64
    /// Observation order, not accounting order.
    let members: [Member]

    init(submission: SharedMediaOrdinarySubmission, holds: SharedMediaOrdinaryHoldCohort) throws {
        try submission.validate(holds: holds)
        let accepted = try holds.acceptances()
        format = .v1
        requestSHA256 = SharedMediaAcquisitionEncoding.digest(try submission.encoded())
        guard let first = holds.requests.first else { throw SharedMediaStorageFailure.conflict }
        inventoryRevision = try SharedMediaStoragePolicy.add(first.inventoryRevision, 1)
        members = try submission.members.map { member in
            guard let request = holds.requests.first(where: { $0.id == member.holdID }),
                  let receipt = accepted[member.holdID] else { throw SharedMediaStorageFailure.conflict }
            return Member(holdID: member.holdID,
                acceptanceSHA256: SharedMediaAcquisitionEncoding.digest(try receipt.encoded(request: request)))
        }
    }

    func validate(submission: SharedMediaOrdinarySubmission, holds: SharedMediaOrdinaryHoldCohort) throws {
        guard try self == Self(submission: submission, holds: holds) else { throw SharedMediaStorageFailure.conflict }
    }
    func encoded(submission: SharedMediaOrdinarySubmission, holds: SharedMediaOrdinaryHoldCohort) throws -> Data {
        try validate(submission: submission, holds: holds)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes)
    }
    static func decode(_ data: Data, sha256: String, submission: SharedMediaOrdinarySubmission,
                       holds: SharedMediaOrdinaryHoldCohort) throws -> Self {
        try SharedMediaOrdinaryHoldEncoding.requireDigest(data, sha256: sha256)
        let value: Self = try SharedMediaAcquisitionEncoding.decode(data,
            maximum: SharedMediaOrdinaryHoldEncoding.maximumEnvelopeBytes)
        guard try value.encoded(submission: submission, holds: holds) == data else {
            throw SharedMediaStorageFailure.conflict
        }
        return value
    }
}
