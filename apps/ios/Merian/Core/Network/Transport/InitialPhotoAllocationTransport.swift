import Foundation

/// One bounded authenticated attempt. Status can expire preparation remotely;
/// neither action uses generic retries, refresh, redirects or inference routes.
struct InitialPhotoAllocationTransport {
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher
    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func perform(_ candidate: InitialPhotoAllocationRequest,
                 validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                 validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> InitialPhotoAllocationReply {
        guard candidate.projection == .legacy else { throw SharedMediaStorageFailure.closed }
        let data = try await exchange(candidate, validateAttempt: validateAttempt)
        let reply = try InitialPhotoAllocationReply(data: data, request: candidate)
        try await validateResponse()
        return reply
    }

    func performRoles(_ candidate: InitialPhotoAllocationRequest,
                      validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                      validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> InitialPhotoAllocationRoleReply {
        guard (candidate.projection == .roles && candidate.allocation.version == 2)
            || (candidate.projection == .boundRoles && candidate.allocation.version == 6) else { throw SharedMediaStorageFailure.closed }
        let data = try await exchange(candidate, validateAttempt: validateAttempt)
        let saved = candidate.allocation.roleMapping.flatMap { mapping in
            candidate.allocation.receipt.map { InitialPhotoAllocationRoleReply.Projection(receipt: $0, entries: mapping.entries, backendBinding: candidate.allocation.backendBinding) }
        }
        let reply = try InitialPhotoAllocationRoleReply(data: data, request: candidate, saved: candidate.projection == .boundRoles && candidate.allocation.backendBinding == nil ? nil : saved)
        try await validateResponse()
        return reply
    }

    enum TransferPhase: Sendable {
        case role, cohort
        var timeout: TimeInterval { self == .role ? 5 : 35 }
    }

    @MainActor func verifyCohort(_ fresh: SharedMediaNativePhotoAllocationAccess.VerificationStart) async throws -> Bool {
        let value = try fresh.consume()
        guard value.version == 17, let receipt = value.receipt, let binding = value.backendBinding else {
            throw SharedMediaStorageFailure.closed
        }
        let scan = value.claim.observationID.uuidString.lowercased(), backend = binding.generation.uuidString.lowercased()
        let fields: [String: Any] = ["version": 3, "action": "verify_cohort", "scan_id": scan,
            "assignment_digest": receipt.assignmentDigest, "candidate_canonical": value.claim.candidateCanonical,
            "allocation_created_at_ms": receipt.createdAtMilliseconds, "allocation_expires_at_ms": receipt.expiresAtMilliseconds,
            "backend_generation": backend, "backend_configuration_digest": binding.configurationDigest]
        let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        guard body.count <= 2 * 1_048_576 + 4096 else { throw SharedMediaStorageFailure.capacity }
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "initial-photo-transfer")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: TransferPhase.cohort.timeout)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let reply = try await dispatcher.performInitialPhotoTransfer(.init(request: request, body: body, onRequestBodySent: nil,
            authTransitionOwner: nil, expectedAuthUserID: value.claim.profile.ownerID, validateAttempt: { try fresh.validate() }), phase: .cohort)
        try Task.checkCancellation(); try fresh.validate()
        guard let http = reply.response as? HTTPURLResponse, http.statusCode == 200, http.mimeType?.lowercased() == "application/json",
              reply.data.count <= 2048, let row = try JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
              Set(row.keys) == ["version", "outcome", "authority", "scan_id", "assignment_digest", "candidate_digest",
                                "backend_generation", "backend_configuration_digest"],
              try ObservationHistoryPage.integer(row["version"], maximum: 3) == 3, row["authority"] as? String == "none",
              row["scan_id"] as? String == scan, row["assignment_digest"] as? String == receipt.assignmentDigest,
              row["candidate_digest"] as? String == value.claim.candidateDigest, row["backend_generation"] as? String == backend,
              row["backend_configuration_digest"] as? String == binding.configurationDigest,
              let outcome = row["outcome"] as? String, ["admitted", "held"].contains(outcome) else { throw MerianError.invalidResponse }
        return outcome == "admitted"
    }

    /// Trusted injected sender only. The retained owner consumes the fresh
    /// continuation before calling, and rechecks it again when decoding the reply.
    /// No ordinary caller or server endpoint is installed by this adapter.
    func performTransfer(_ candidate: InitialPhotoTransferRequest,
                         validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> Data {
        try await candidate.consumeAuthenticatedIssue()
        try Task.checkCancellation()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "initial-photo-transfer")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = candidate.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await dispatcher.performInitialPhotoTransfer(.init(request: request, body: candidate.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: candidate.allocation.claim.profile.ownerID,
            validateAttempt: validateAttempt))
        try await validateAttempt()
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "initial_photo_transfer_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        return result.data
    }

    private func exchange(_ candidate: InitialPhotoAllocationRequest,
                          validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> Data {
        try Task.checkCancellation()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "initial-photo-allocation")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = candidate.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await dispatcher.performInitialPhotoAllocation(.init(request: request, body: candidate.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: candidate.allocation.claim.profile.ownerID,
            validateAttempt: validateAttempt))
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "initial_photo_allocation_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        return result.data
    }
}
