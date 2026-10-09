import Foundation

/// One fixed mutation route. Lost answers retain the original candidate; this never runs inference.
struct ObservationSourceReservationTransport {
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher

    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func reserve(_ candidate: ObservationSourceReservationRequest, ownerID: UUID,
                 validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                 validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationSourceReservationReply {
        try Task.checkCancellation()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "reserve-observation-analysis-source")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = candidate.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("3", forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
        // Direct single attempt: no generic executor, Auth refresh, route retry or idempotency replay.
        let result = try await dispatcher.performSourceReservation(.init(request: request, body: candidate.body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, validateAttempt: validateAttempt))
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        if response.statusCode == 409, response.mimeType?.lowercased() == "application/json",
           Self.isExactConflict(result.data) {
            try await validateResponse()
            throw ObservationSourceReservationConflict(request: candidate, ownerID: ownerID)
        }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "analysis_history_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        let reply = try ObservationSourceReservationReply(data: result.data, request: candidate, ownerID: ownerID)
        // A known answer survives dispatch cancellation only under the caller's exact settlement scope.
        try await validateResponse()
        return reply
    }

    private static func isExactConflict(_ data: Data) -> Bool {
        guard data.count <= ObservationSourceReservationReply.maximumBytes,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["error", "code", "request_id"],
              row["code"] as? String == "analysis_history_operation_conflict",
              let message = row["error"] as? String, message.utf16.count <= 500,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? ObservationHistoryPage.uuid(row["request_id"])) != nil else { return false }
        return true
    }
}

/// A definite conflict under the original scope, never a release receipt or execution permission.
struct ObservationSourceReservationConflict: Error, Equatable, Sendable {
    let request: ObservationSourceReservationRequest
    let ownerID: UUID
}
