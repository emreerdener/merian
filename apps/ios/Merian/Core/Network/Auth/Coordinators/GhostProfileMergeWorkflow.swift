import Foundation

@MainActor
enum GhostProfileMergeWorkflow {
    /// Proof removal is the final local mutation after the idempotent server
    /// completion, purchase sync, evidence rebind, and every cancellation
    /// boundary have succeeded.
    static func finalizeHandoff(
        completeServerHandoff: @MainActor () async throws -> Void,
        synchronizeProviderPurchases: @MainActor () async throws -> Void,
        rebindAndSynchronizeLocalEvidence: @MainActor () async throws -> Void,
        clearPendingHandoff: @MainActor () throws -> Void
    ) async throws {
        try Task.checkCancellation()
        try await completeServerHandoff()
        try Task.checkCancellation()
        try await synchronizeProviderPurchases()
        try Task.checkCancellation()
        try await rebindAndSynchronizeLocalEvidence()
        try Task.checkCancellation()
        try clearPendingHandoff()
    }
}
