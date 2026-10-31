import Foundation

/// Closed saved-work projection for the dormant facade. These bytes confer no
/// dispatch or upload authority; issue requires the owner's fresh continuation.
struct InitialPhotoTransferRequest: Sendable {
    enum Action: String, Sendable { case issue, status }
    let allocation: SharedMediaNativePhotoAllocation
    let action: Action
    let body: Data

    init(allocation: SharedMediaNativePhotoAllocation, action: Action) throws {
        _ = try allocation.encoded()
        guard (4...5).contains(allocation.version) || (8...12).contains(allocation.version),
              let receipt = allocation.receipt, let transfer = allocation.transferReservation else {
            throw SharedMediaStorageFailure.closed
        }
        if action == .issue {
            guard allocation.version == 9 || allocation.version == 11, allocation.ticketRequestStarted == true,
                  allocation.remoteAttempt == nil, allocation.backendBinding != nil else {
                throw SharedMediaStorageFailure.closed
            }
        }
        var fields: [String: Any] = ["version": 1, "action": action.rawValue,
            "scan_id": allocation.claim.observationID.uuidString.lowercased(),
            "assignment_digest": receipt.assignmentDigest,
            "object_id": transfer.selection.objectID.uuidString.lowercased(),
            "allocation_created_at_ms": receipt.createdAtMilliseconds,
            "allocation_expires_at_ms": receipt.expiresAtMilliseconds]
        if action == .issue { fields["candidate_canonical"] = allocation.claim.candidateCanonical }
        let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        guard body.count <= 2 * 1_048_576 + 4096 else { throw SharedMediaStorageFailure.capacity }
        self.allocation = allocation; self.action = action; self.body = body
    }
}
