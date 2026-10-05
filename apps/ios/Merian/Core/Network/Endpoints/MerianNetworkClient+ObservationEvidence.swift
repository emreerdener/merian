import Foundation

extension MerianNetworkClient {
    /// A closed route set keeps exact-byte replay out of the generic endpoint bridge.
    enum ObservationOperation {
        case uploadEvidence(@MainActor @Sendable () throws -> Void)
        case analyze(IdentificationDispatchAuthorization)

        var function: String {
            switch self {
            case .uploadEvidence: return "upload-observation-evidence"
            case .analyze: return "analyze-observation"
            }
        }

        func request(url: URL, body: Data, ownerID: UUID) -> AuthenticatedRequestExecutor.Request {
            var request = AuthenticatedRequestExecutor.Request(url: url, method: "POST", body: body,
                timeoutInterval: 130, idempotencyKey: nil, allowsTransientTransportRetry: false,
                allowsUnauthorizedSessionRecovery: false, onRequestBodySent: nil,
                authTransitionOwner: nil, expectedAuthUserID: ownerID)
            switch self {
            case let .uploadEvidence(validate):
                request.contentType = .octetStream
                request.validateAttempt = validate
            case let .analyze(authorization):
                request.identificationAuthorization = authorization
            }
            return request
        }
    }

    /// Admission or recovery of the exact persisted child; funding and dispatch are server-owned.
    func analyzeObservation(_ request: ObservationReanalysisRequest, ownerID: UUID,
                            authorization: IdentificationDispatchAuthorization) async throws -> ObservationAnalysisReceipt {
        try Task.checkCancellation()
        guard authorization.recipient == request.processor else { throw MerianError.invalidResponse }
        try await authorization.validate()
        let data = try await performAuthenticatedObservationRequest(.analyze(authorization), body: request.body, expectedAuthUserID: ownerID)
        try Task.checkCancellation()
        return try ObservationAnalysisReceipt.decode(data, request: request)
    }

    /// The caller persists IDs and bytes first and owns recovery after every uncertain response.
    func uploadObservationEvidence(_ upload: ObservationEvidenceUpload, ownerID: UUID,
                                   validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationEvidenceUploadReceipt {
        try Task.checkCancellation()
        try await validateAttempt()
        let prepared = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try upload.prepare()
        }
        try Task.checkCancellation()
        try await validateAttempt()
        let data = try await performAuthenticatedObservationRequest(.uploadEvidence(validateAttempt), body: prepared.body, expectedAuthUserID: ownerID)
        try Task.checkCancellation()
        try await validateAttempt()
        return try ObservationEvidenceUploadReceipt.decode(data, request: prepared)
    }
}
