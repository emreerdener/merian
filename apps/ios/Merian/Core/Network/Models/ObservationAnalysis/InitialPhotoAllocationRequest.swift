import Foundation

/// Fixed candidate retained by the receiving owner. Construction grants no
/// right to create; only its live, acknowledged claim transition can do that.
struct InitialPhotoAllocationRequest: Sendable {
    enum Action: String, Sendable { case create, status }
    let allocation: SharedMediaNativePhotoAllocation
    let action: Action
    let body: Data

    init(allocation: SharedMediaNativePhotoAllocation, action: Action) throws {
        _ = try allocation.encoded()
        guard action != .create || allocation.receipt == nil else { throw SharedMediaStorageFailure.closed }
        var fields: [String: Any] = ["version": 1, "action": action.rawValue,
            "candidate_canonical": allocation.claim.candidateCanonical]
        if action == .status { fields["saved_assignment_digest"] = (allocation.receipt?.assignmentDigest as Any?) ?? NSNull() }
        let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        guard body.count <= 2 * 1_048_576 + 4096 else { throw SharedMediaStorageFailure.capacity }
        self.allocation = allocation; self.action = action; self.body = body
    }
}

/// Association to the request, not upload, inference, release or remote-usability evidence.
enum InitialPhotoAllocationReply: Equatable, Sendable {
    static let maximumBytes = 2048
    enum HeldReason: String, Sendable { case notFound = "not_found", expired, cancelled }
    case allocated(SharedMediaNativePhotoAllocation.Receipt)
    case held(HeldReason)

    init(data: Data, request: InitialPhotoAllocationRequest) throws {
        guard data.count <= Self.maximumBytes,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MerianError.invalidResponse
        }
        let common = Self.associationKeys
        try Self.requireAssociation(row, request: request, version: 1)
        switch row["outcome"] as? String {
        case "allocated":
            guard Set(row.keys) == common.union(["assignment_digest", "created_at_ms", "expires_at_ms"]),
                  let digest = row["assignment_digest"] as? String else { throw MerianError.invalidResponse }
            let receipt = try Self.receipt(row, digest: digest, request: request)
            self = .allocated(receipt)
        case "terminal_held":
            guard Set(row.keys) == common.union(["reason"]), let reason = row["reason"] as? String,
                  let held = HeldReason(rawValue: reason) else { throw MerianError.invalidResponse }
            self = .held(held)
        default: throw MerianError.invalidResponse
        }
    }
    static let associationKeys: Set<String> = ["version", "variant", "authority", "scan_id", "package_id",
        "candidate_digest", "content_digest", "outcome"]

    static func requireAssociation(_ row: [String: Any], request: InitialPhotoAllocationRequest, version: Int) throws {
        let claim = request.allocation.claim
        guard try ObservationHistoryPage.integer(row["version"], maximum: version) == version,
              row["variant"] as? String == "client_prepared_photo", row["authority"] as? String == "none",
              try ObservationHistoryPage.uuid(row["scan_id"]) == claim.observationID,
              try ObservationHistoryPage.uuid(row["package_id"]) == claim.packageID,
              row["candidate_digest"] as? String == claim.candidateDigest,
              row["content_digest"] as? String == claim.contentDigest else { throw MerianError.invalidResponse }
    }

    static func receipt(_ row: [String: Any], digest: String, request: InitialPhotoAllocationRequest) throws -> SharedMediaNativePhotoAllocation.Receipt {
        let receipt = SharedMediaNativePhotoAllocation.Receipt(assignmentDigest: digest,
                createdAtMilliseconds: Int64(try ObservationHistoryPage.integer(row["created_at_ms"], maximum: 8_639_999_998_200_000)),
                expiresAtMilliseconds: Int64(try ObservationHistoryPage.integer(row["expires_at_ms"], maximum: 8_640_000_000_000_000)))
        _ = try request.allocation.settling(receipt)
        return receipt
    }

}
