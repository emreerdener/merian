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

    /// Trusted injected sender only. The retained owner consumes the fresh
    /// continuation before calling, and rechecks it again when decoding the reply.
    /// No ordinary caller or server endpoint is installed by this adapter.
    func performTransfer(_ candidate: InitialPhotoTransferRequest,
                         validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> Data {
        if candidate.action == .issue, candidate.allocation.version != 11 { throw SharedMediaStorageFailure.closed }
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
