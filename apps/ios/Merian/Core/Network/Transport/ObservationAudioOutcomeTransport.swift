import Foundation

/// Fixed read-only recovery. Neither absence nor a returned snapshot authorizes provider dispatch.
struct ObservationAudioOutcomeTransport {
    let baseURL: String
    let dispatcher: AuthenticatedTransportDispatcher

    func read(_ claim: ObservationAudioExecutionStore.Claim,
              validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
              validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> Data? {
        try Task.checkCancellation()
        let work = claim.snapshot.work, intent = work.intent
        guard work.state == .running, work.consumedAttempt != nil else { throw MerianError.invalidResponse }
        let target = ObservationHistoryStateRequest(observation_id: intent.request.observationID.uuidString.lowercased(),
            analysis_id: intent.request.analysisID.uuidString.lowercased())
        struct Parameters: Encodable {
            let p_request: ObservationHistoryStateRequest
            let p_reader = 10
        }
        let body = try JSONEncoder().encode(Parameters(p_request: target))
        let url = try AdmissionRPCRequestPolicy.url(baseURL: baseURL, route: .analysisState)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let reply = try await dispatcher.performAudioOutcomeRead(.init(request: request, body: body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: intent.ownerID, validateAttempt: validateAttempt))
        guard let response = reply.response as? HTTPURLResponse,
              response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        let result: Data?
        if response.statusCode == 200 {
            do {
                let state = try ObservationHistoryState.decode(reply.data, request: target, ownerID: intent.ownerID)
                result = try ObservationReanalysisResult.decode(state.result.bytes, matching: intent.request).bytes
            } catch {
                // Invalid immutable authority is reconciliation failure, never missing evidence.
                throw ObservationHistoryError.invalidSnapshot
            }
        } else if response.statusCode == 404, Self.isExactMissing(reply.data) {
            result = nil
        } else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "analysis_history_unavailable")
        }
        // Do not discard a decoded answer on cancellation; the caller still fences account and scope.
        // Atomic Store.complete rechecks the source and full durable claim before any mutation.
        try await validateResponse()
        return result
    }

    private static func isExactMissing(_ data: Data) -> Bool {
        guard data.count <= 8_192,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys).isSubset(of: ["code", "message", "details", "hint"]),
              row["code"] as? String == "P0002", row["message"] as? String == "analysis_history_not_found" else { return false }
        return ["details", "hint"].allSatisfy { row[$0] == nil || row[$0] is NSNull || row[$0] is String }
    }
}
