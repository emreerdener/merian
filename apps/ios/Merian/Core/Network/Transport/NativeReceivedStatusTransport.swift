import Foundation

/// An explicit probe on the existing status route. No recovery payload, generic
/// retry, inference dispatch or local result import is available here.
struct NativeReceivedStatusTransport {
    typealias Validator = @MainActor @Sendable () throws -> Void
    typealias Send = @MainActor (UUID, UUID, @escaping Validator) async throws -> Data
    static let maximumBytes = 4096
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher
    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func perform(scanID: UUID, ownerID: UUID, validate: @escaping Validator) async throws -> Data {
        try Task.checkCancellation()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "check-scan-status")
        let body = try JSONSerialization.data(withJSONObject: ["scan_id": scanID.uuidString.lowercased()], options: [.sortedKeys])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await dispatcher.performNativeReceivedStatus(.init(request: request, body: body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, validateAttempt: validate))
        try Task.checkCancellation(); try await validate()
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "received_status_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json", result.data.count <= Self.maximumBytes else {
            throw MerianError.invalidResponse
        }
        return result.data
    }
}
