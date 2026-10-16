import Foundation

/// Inert upload seam. The durable owner supplies saved bytes and both scope fences.
struct ObservationVideoEvidenceTransport {
    static let requestSeconds: TimeInterval = 130
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher

    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func upload(_ wire: ObservationVideoEvidenceWireRequest, ownerID: UUID,
                previous: ObservationVideoEvidenceReceipt? = nil,
                validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationVideoEvidenceReceipt {
        try Task.checkCancellation()
        // A prior snapshot is evidence for this exact cohort only, never a caller-selected new association.
        if let previous {
            _ = try ObservationVideoEvidenceReceipt(data: previous.data, request: wire.request, ownerID: ownerID)
        }
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "upload-observation-video")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestSeconds)
        request.httpMethod = "POST"; request.httpBody = wire.body
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("3", forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
        let result = try await dispatcher.performVideoEvidenceUpload(.init(request: request, body: wire.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, validateAttempt: validateAttempt))
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "analysis_history_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        let receipt = try ObservationVideoEvidenceReceipt(data: result.data, request: wire.request, ownerID: ownerID, previous: previous)
        guard receipt.items.contains(where: { $0.metadata.artifact.mediaID == wire.mediaID && $0.readyAt != nil }) else {
            throw MerianError.invalidResponse
        }
        // A known saved upload answer needs settlement authority, not renewed dispatch permission.
        try await validateResponse()
        return receipt
    }
}
