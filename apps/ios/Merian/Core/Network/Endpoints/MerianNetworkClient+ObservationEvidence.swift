import Foundation

extension MerianNetworkClient {
    /// A closed route set keeps exact-byte replay out of the generic endpoint bridge.
    enum ObservationOperation {
        case uploadEvidence
        case analyze(IdentificationDispatchAuthorization)

        var function: String {
            switch self {
            case .uploadEvidence: return "upload-observation-evidence"
            case .analyze: return "analyze-observation"
            }
        }

        var authorization: IdentificationDispatchAuthorization? {
            switch self {
            case .uploadEvidence: return nil
            case let .analyze(value): return value
            }
        }

        var contentType: AuthenticatedRequestExecutor.ContentType {
            switch self {
            case .uploadEvidence: return .octetStream
            case .analyze: return .json
            }
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
    func uploadObservationEvidence(_ upload: ObservationEvidenceUpload, ownerID: UUID) async throws -> ObservationEvidenceUploadReceipt {
        let prepared = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try upload.prepare()
        }
        try Task.checkCancellation()
        let data = try await performAuthenticatedObservationRequest(.uploadEvidence, body: prepared.body, expectedAuthUserID: ownerID)
        try Task.checkCancellation()
        return try ObservationEvidenceUploadReceipt.decode(data, request: prepared)
    }
}
