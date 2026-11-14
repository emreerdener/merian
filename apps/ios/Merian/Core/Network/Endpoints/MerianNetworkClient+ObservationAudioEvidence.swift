import Foundation

extension MerianNetworkClient {
    /// Only a durable owner may call this with its unchanged IDs/bytes and current claim.
    func uploadObservationAudioEvidence(
        _ upload: ObservationAudioEvidenceUpload, ownerID: UUID,
        validateAttempt: @escaping @MainActor @Sendable () throws -> Void
    ) async throws -> ObservationAudioEvidenceUploadReceipt {
        try Task.checkCancellation()
        try await validateAttempt()
        let prepared = try await DetachedWork.value(category: .inferenceRequestPreparation) { try upload.prepare() }
        try Task.checkCancellation()
        try await validateAttempt()
        let data = try await performAuthenticatedObservationRequest(.uploadAudioEvidence(validateAttempt),
            body: prepared.body, expectedAuthUserID: ownerID)
        try Task.checkCancellation()
        try await validateAttempt()
        return try ObservationAudioEvidenceUploadReceipt.decode(data, request: prepared)
    }
}
