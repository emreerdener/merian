import Foundation

/// Reads the sealed result of an already dispatched private capture. A held or
/// uncertain response never authorizes another primary identification request.
struct CaptureCompletionTransport {
    static let maximumRequestBytes = 1_048_576
    static let maximumResponseBytes = 1_052_672
    typealias Validator = @MainActor @Sendable () throws -> Void
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher

    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func recover(_ plan: CaptureInitialEvidencePlan, validate: @escaping Validator) async throws -> Data? {
        try Task.checkCancellation(); try await validate()
        let body = try Self.request(plan)
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "check-scan-status")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("capture-completion-v1", forHTTPHeaderField: "X-Merian-Initial-Recovery")
        let result = try await dispatcher.performNativeInitialRecovery(.init(request: request, body: body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: plan.ownerID,
            validateAttempt: validate), phase: .captureCompletion)
        try Task.checkCancellation(); try await validate()
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "capture_completion_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json" else { throw MerianError.invalidResponse }
        let completion = try Self.decode(result.data, plan: plan)
        try Task.checkCancellation(); try await validate()
        return completion
    }

    static func request(_ plan: CaptureInitialEvidencePlan) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["initial_recovery": [
            "version": 1, "phase": "capture-completion", "capture_plan": plan.object
        ]], options: [.sortedKeys, .withoutEscapingSlashes])
        guard body.count <= maximumRequestBytes else { throw MerianError.payloadTooLarge }
        return body
    }

    /// Identity is checked here; the existing result writer still validates the
    /// full result, funding and evidence proof before committing anything locally.
    static func decode(_ bytes: Data, plan: CaptureInitialEvidencePlan) throws -> Data? {
        guard bytes.count <= maximumResponseBytes else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: bytes),
            keys: ["version", "phase", "owner_id", "scan_id", "generation", "status", "completion"])
        guard try ObservationHistoryPage.integer(row["version"]) == 1,
              row["phase"] as? String == "capture-completion",
              row["owner_id"] as? String == plan.ownerID.uuidString.lowercased(),
              row["scan_id"] as? String == plan.scanID.uuidString.lowercased(),
              row["generation"] as? String == plan.generation.uuidString.lowercased() else {
            throw MerianError.invalidResponse
        }
        if row["status"] as? String == "held", row["completion"] is NSNull { return nil }
        guard row["status"] as? String == "completed", let completion = row["completion"] as? [String: Any],
              let evidence = completion["initial_evidence"] else { throw MerianError.invalidResponse }
        let proof = try OrdinaryInitialEvidenceProof(JSONDecoder().decode(InitialEvidenceCompletionDTO.self,
            from: JSONSerialization.data(withJSONObject: evidence)))
        guard proof.submission == OrdinaryInitialSubmissionIdentity(ownerID: plan.ownerID,
            scanID: plan.scanID, generation: plan.generation) else { throw MerianError.invalidResponse }
        let result = try JSONSerialization.data(withJSONObject: completion, options: [.sortedKeys, .withoutEscapingSlashes])
        guard result.count <= OrdinaryInferenceCompletion.maximumBytes else { throw MerianError.invalidResponse }
        return result
    }
}
