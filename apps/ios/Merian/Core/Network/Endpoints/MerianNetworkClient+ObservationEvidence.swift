import Foundation

extension MerianNetworkClient {
    /// The caller persists IDs and bytes first and owns recovery after every uncertain response.
    func uploadObservationEvidence(_ upload: ObservationEvidenceUpload, ownerID: UUID) async throws -> ObservationEvidenceUploadReceipt {
        let prepared = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try upload.prepare()
        }
        try Task.checkCancellation()
        let data = try await performAuthenticatedObservationEvidenceUpload(body: prepared.body, expectedAuthUserID: ownerID)
        try Task.checkCancellation()
        return try ObservationEvidenceUploadReceipt.decode(data, request: prepared)
    }
}
