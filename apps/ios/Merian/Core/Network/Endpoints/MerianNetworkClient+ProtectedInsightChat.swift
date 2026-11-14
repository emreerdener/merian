import Foundation

extension MerianNetworkClient {
    /// Exact immutable request only. Durable delivery supplies both claim and post-await scope fences.
    func sendProtectedInsightChat(_ request: ProtectedInsightChatRequest, ownerID: UUID, claimExpiresAt: Date,
                                  validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                                  validateResponse: @escaping @MainActor @Sendable () throws -> Void) async throws -> ProtectedInsightChatReply {
        try await observationHistoryMutationTransport.submit(request, expectedAuthUserID: ownerID,
            claimExpiresAt: claimExpiresAt, validateAttempt: validateAttempt, validateResponse: validateResponse)
    }
}
