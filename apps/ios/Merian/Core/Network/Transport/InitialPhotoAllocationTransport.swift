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
        let reply = try InitialPhotoAllocationReply(data: result.data, request: candidate)
        try await validateResponse()
        return reply
    }
}
