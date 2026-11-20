import Foundation

/// Closed saved-work projection for the dormant facade. These bytes confer no
/// dispatch or upload authority; issue requires the owner's fresh continuation.
struct InitialPhotoTransferRequest: Sendable {
    typealias Send = @MainActor (InitialPhotoTransferRequest, @escaping @MainActor @Sendable () throws -> Void) async throws -> Data
    @MainActor static func validating(_ send: @escaping Send, _ validate: @escaping @MainActor @Sendable () throws -> Void) -> Send {
        { request, check in
            try validate()
            let bytes = try await send(request, { try check(); try validate() })
            try validate()
            return bytes
        }
    }
    enum Action: String, Sendable { case issue, status, roleProgress = "role_progress" }
    let allocation: SharedMediaNativePhotoAllocation
    let action: Action
    let body: Data
    private var followingTicket: SharedMediaNativePhotoTicketContinuation?

    @MainActor func bindingFreshExchange(_ ticket: SharedMediaNativePhotoTicketContinuation) throws -> Self {
        guard allocation == ticket.allocation, action == .issue else { throw SharedMediaStorageFailure.stale }
        try ticket.validateConsumed()
        var request = self
        request.followingTicket = ticket
        return request
    }

    @MainActor func consumeAuthenticatedIssue() throws {
        guard action == .issue else { return }
        if allocation.version == 11 { return }
        guard allocation.version == 14, let followingTicket else { throw SharedMediaStorageFailure.closed }
        try followingTicket.consumeFollowingExchange(for: allocation)
    }

    init(allocation: SharedMediaNativePhotoAllocation, action: Action) throws {
        _ = try allocation.encoded()
        guard (4...5).contains(allocation.transferPhase) || (8...13).contains(allocation.transferPhase),
              let receipt = allocation.receipt, let transfer = allocation.transferReservation else {
            throw SharedMediaStorageFailure.closed
        }
        if action == .issue {
            guard allocation.transferPhase == 9 || allocation.transferPhase == 11, allocation.ticketRequestStarted == true,
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
        if action == .roleProgress {
            guard (12...13).contains(allocation.transferPhase), allocation.backendBinding != nil,
                  let attempt = allocation.remoteAttempt, attempt.state == .mayHaveIssued,
                  attempt.writeClosed else { throw SharedMediaStorageFailure.closed }
            fields["version"] = 2
            fields["attempt_id"] = attempt.id.uuidString.lowercased()
        }
        if action == .issue { fields["candidate_canonical"] = allocation.claim.candidateCanonical }
        let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        guard body.count <= 2 * 1_048_576 + 4096 else { throw SharedMediaStorageFailure.capacity }
        self.allocation = allocation; self.action = action; self.body = body
    }
}

/// Inert proof for the original transfer only. The closure policy is learned
/// from the authenticated observation of the original attempt. It cannot
/// select a new backend, release the transfer slot or authorize another PUT.
struct InitialPhotoRoleProgress: Equatable, Sendable {
    let selection: SharedMediaNativePhotoRoleMapping.Entry
    let attemptID: UUID
    let policyDigest: String
    let observedAt: String
    let canonicalReceipt: Data
    private let original: SharedMediaNativePhotoAllocation

    init(data: Data, matching request: InitialPhotoTransferRequest) throws {
        let allocation = request.allocation
        guard request.action == .roleProgress, (12...13).contains(allocation.transferPhase),
              let receipt = allocation.receipt, let transfer = allocation.transferReservation,
              let backend = allocation.backendBinding, let attempt = allocation.remoteAttempt,
              attempt.writeClosed, attempt.state == .mayHaveIssued,
              data.count <= 2048, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "outcome", "authority", "owner_id", "scan_id", "assignment_digest",
                "object_id", "attempt_id", "role", "byte_count", "content_type", "sha256", "backend_generation",
                "backend_configuration_digest", "policy_digest", "observed_at"],
              try ObservationHistoryPage.integer(row["version"], maximum: 2) == 2,
              row["outcome"] as? String == "live_role_observed", row["authority"] as? String == "none",
              try ObservationHistoryPage.uuid(row["owner_id"]) == allocation.claim.profile.ownerID,
              try ObservationHistoryPage.uuid(row["scan_id"]) == allocation.claim.observationID,
              row["assignment_digest"] as? String == receipt.assignmentDigest,
              try ObservationHistoryPage.uuid(row["object_id"]) == transfer.selection.objectID,
              try ObservationHistoryPage.uuid(row["attempt_id"]) == attempt.id,
              row["role"] as? String == transfer.selection.role.rawValue,
              try ObservationHistoryPage.integer(row["byte_count"], maximum: 33_554_432) == transfer.byteCount,
              row["content_type"] as? String == (try transfer.declaredContentType(claim: allocation.claim)),
              row["sha256"] as? String == transfer.sha256,
              try ObservationHistoryPage.uuid(row["backend_generation"]) == backend.generation,
              row["backend_configuration_digest"] as? String == backend.configurationDigest,
              let policy = row["policy_digest"] as? String, SharedMediaAcquisitionEncoding.isHash(policy),
              let timestamp = row["observed_at"] as? String,
              timestamp.utf8.count == 27,
              timestamp.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$"#,
                              options: .regularExpression) != nil,
              let second = try? Date.ISO8601FormatStyle().parse(String(timestamp.prefix(19)) + "Z"),
              second.formatted(.iso8601) == String(timestamp.prefix(19)) + "Z",
              let subsecond = Int64(timestamp.dropFirst(20).prefix(3)) else { throw MerianError.invalidResponse }
        // The server stores microseconds. Compare the integral millisecond
        // bucket to the original half-open allocation clock; retain exact text.
        let milliseconds = Int64(second.timeIntervalSince1970.rounded()) * 1000 + subsecond
        guard milliseconds >= attempt.createdAtMilliseconds, milliseconds < receipt.expiresAtMilliseconds else {
            throw MerianError.invalidResponse
        }
        canonicalReceipt = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard canonicalReceipt.count <= 2048 else { throw MerianError.invalidResponse }
        if let saved = allocation.liveRoleReceipt, saved != canonicalReceipt { throw MerianError.invalidResponse }
        original = allocation; selection = transfer.selection; attemptID = attempt.id
        policyDigest = policy; observedAt = timestamp
    }

    func requireOriginal(_ allocation: SharedMediaNativePhotoAllocation) throws {
        guard allocation == original else { throw SharedMediaStorageFailure.stale }
    }
}
