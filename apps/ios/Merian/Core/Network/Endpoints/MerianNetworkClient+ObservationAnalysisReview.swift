import Foundation

extension MerianNetworkClient {
    func observationConfirmationUndo(
        _ lookup: ObservationConfirmationUndoLookup,
        ownerID: UUID,
        validateAttempt: @escaping @MainActor @Sendable () throws -> Void
    ) async throws -> ObservationConfirmationUndoReply {
        try await observationHistoryMutationTransport.confirmationUndo(lookup, ownerID: ownerID, validateAttempt: validateAttempt)
    }

    /// Exact operation replay belongs to the durable owner; this method never rebases or projects authority.
    func reviewObservationAnalysis(_ request: ObservationAnalysisReviewRequest, ownerID: UUID,
                                   validateAttempt: @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationAnalysisReviewReceipt {
        let data = try await observationHistoryMutationTransport.submit(request, expectedAuthUserID: ownerID, validateAttempt: validateAttempt)
        return try ObservationAnalysisReviewReceipt.decode(data, request: request)
    }
}
