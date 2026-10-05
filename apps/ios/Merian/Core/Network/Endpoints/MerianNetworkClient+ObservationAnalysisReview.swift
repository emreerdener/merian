import Foundation

extension MerianNetworkClient {
    /// Exact operation replay belongs to the durable owner; this method never rebases or projects authority.
    func reviewObservationAnalysis(_ request: ObservationAnalysisReviewRequest, ownerID: UUID) async throws -> ObservationAnalysisReviewReceipt {
        let data = try await observationHistoryReviewTransport.submit(request, expectedAuthUserID: ownerID)
        return try ObservationAnalysisReviewReceipt.decode(data, request: request)
    }
}
