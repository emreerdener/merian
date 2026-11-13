import Foundation

/// Explicit reads on the existing status owner. Recovery methods are prepared
/// but unwired; no generic retry, inference dispatch or result import lives here.
struct NativeReceivedStatusTransport {
    typealias Validator = @MainActor @Sendable () throws -> Void
    typealias Send = @MainActor (UUID, UUID, @escaping Validator) async throws -> Data
    static let maximumBytes = 4096
    enum RecoveryPhase: String, Sendable {
        case admission, completion
        var maximumResponseBytes: Int {
            self == .admission ? 8192 : InitialCompletionDocuments.statusResponseMaximumBytes
        }
        var maximumRequestBytes: Int { self == .admission ? 2 * 1_048_576 + 4096 : 8192 }
    }
    private let baseURL: String
    private let dispatcher: AuthenticatedTransportDispatcher
    init(baseURL: String, dispatcher: AuthenticatedTransportDispatcher) {
        self.baseURL = baseURL; self.dispatcher = dispatcher
    }

    func perform(scanID: UUID, ownerID: UUID, validate: @escaping Validator) async throws -> Data {
        try Task.checkCancellation()
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "check-scan-status")
        let body = try ScanObservationResponse.request(ownerID: ownerID, scanID: scanID)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("observe-v1", forHTTPHeaderField: "X-Merian-Initial-Recovery")
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
        _ = try ScanObservationResponse.decode(result.data, ownerID: ownerID, scanID: scanID)
        return result.data
    }

    func recoverAdmission(_ original: InitialCompletionDocuments.CpmBinding,
                          validate: @escaping Validator) async throws -> Data {
        guard original.candidateCanonical.utf8.count <= 1_048_576 else { throw MerianError.invalidResponse }
        let fields = ["owner_id": original.ownerID, "scan_id": original.scanID,
            "candidate_canonical": original.candidateCanonical, "candidate_digest": original.candidateDigest,
            "content_digest": original.contentDigest, "assignment_digest": original.assignmentDigest,
            "backend_generation": original.backendGeneration, "backend_configuration_digest": original.backendConfigurationDigest]
        let bytes = try await recovery(.admission, original: fields, owner: original.ownerID,
            scan: original.scanID, validate: validate)
        _ = try InitialCompletionDocuments.CpmAdmission(acknowledgement: bytes, original: original)
        try Task.checkCancellation(); try await validate()
        return bytes
    }

    func recoverCompletion(_ admission: InitialCompletionDocuments.CpmAdmission,
                           validate: @escaping Validator) async throws -> InitialCompletionDocuments.CpmAcquisition? {
        guard let source = try InitialAnalysisCanonical.parse(admission.admission).object,
              let owner = source["owner_id"]?.string, let scan = source["scan_id"]?.string else { throw MerianError.invalidResponse }
        var fields: [String: Any] = [:]
        for (key, value) in source {
            switch value {
            case let .string(text): fields[key] = text
            case let .integer(number): fields[key] = number
            default: throw MerianError.invalidResponse
            }
        }
        let bytes = try await recovery(.completion, original: fields, owner: owner, scan: scan, validate: validate)
        let result = try InitialCompletionDocuments.statusAcquisition(bytes, admission: admission)
        try Task.checkCancellation(); try await validate()
        return result
    }

    private func recovery(_ phase: RecoveryPhase, original: [String: Any], owner: String, scan: String,
                          validate: @escaping Validator) async throws -> Data {
        try Task.checkCancellation(); try await validate()
        guard let ownerID = UUID(uuidString: owner), ownerID.uuidString.lowercased() == owner,
              let scanID = UUID(uuidString: scan), scanID.uuidString.lowercased() == scan else { throw MerianError.invalidResponse }
        let body = try JSONSerialization.data(withJSONObject: ["initial_recovery": ["version": 1, "phase": phase.rawValue, "original": original]], options: [.sortedKeys])
        guard body.count <= phase.maximumRequestBytes else { throw MerianError.invalidResponse }
        let url = try EdgeFunctionRoutePolicy.endpointURL(baseURL: baseURL, function: "check-scan-status")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(phase.rawValue + "-v1", forHTTPHeaderField: "X-Merian-Initial-Recovery")
        let result = try await dispatcher.performNativeInitialRecovery(.init(request: request, body: body,
            onRequestBodySent: nil, authTransitionOwner: nil, expectedAuthUserID: ownerID, validateAttempt: validate), phase: phase)
        try Task.checkCancellation(); try await validate()
        guard let response = result.response as? HTTPURLResponse else { throw MerianError.invalidResponse }
        guard response.statusCode == 200 else {
            throw MerianError.httpError(statusCode: response.statusCode, message: "initial_recovery_unavailable")
        }
        guard response.mimeType?.lowercased() == "application/json", result.data.count <= phase.maximumResponseBytes else {
            throw MerianError.invalidResponse
        }
        return result.data
    }
}
