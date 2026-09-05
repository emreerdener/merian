import Foundation

@MainActor
enum PurchaseIdentitySignOutWorkflow {
    /// Orders the ordinary sign-out and replacement anonymous-session phases.
    static func performUserSignOutTransition(
        performSignOut: @MainActor () async -> Void,
        initializeAnonymousSession: @MainActor () async -> Bool
    ) async -> Bool {
        await performSignOut()
        return await initializeAnonymousSession()
    }

    /// Treats durable handoff preparation as the sign-out commit point. A
    /// failure before it leaves the linked session open; a later failure keeps
    /// the persisted proof available for recovery.
    static func performPurchaseSafeSignOutTransition(
        prepareAndPersistHandoff: @MainActor () async throws -> Void,
        performSignOut: @MainActor () async -> Void,
        initializeAnonymousSession: @MainActor () async -> Bool,
        completeHandoff: @MainActor () async throws -> Void,
        reportFailure: @MainActor (Error) -> Void
    ) async -> Bool {
        do {
            try await prepareAndPersistHandoff()
            await performSignOut()
            guard await initializeAnonymousSession() else { return false }
            try await completeHandoff()
            return true
        } catch {
            reportFailure(error)
            return false
        }
    }

    /// Keeps proof removal as the final mutation after every provider, server,
    /// entitlement, cancellation, and destination-session check succeeds.
    static func finalizeSignOutPurchaseHandoff(
        bindDestination: @MainActor () async throws -> Void,
        verifyBoundDestinationSession: @MainActor () async throws -> Void,
        linkProviderIdentity: @MainActor () async throws -> Void,
        verifyLinkedDestinationSession: @MainActor () async throws -> Void,
        synchronizeStorePurchases: @MainActor () async throws -> Void,
        completeServerHandoff: @MainActor () async throws -> Void,
        refreshServerEntitlement: @MainActor () async throws -> Bool,
        verifyFinalDestinationSession: @MainActor () async throws -> Void,
        clearPendingHandoff: @MainActor () throws -> Void
    ) async throws {
        try Task.checkCancellation()
        try await bindDestination()
        try Task.checkCancellation()
        try await verifyBoundDestinationSession()
        try Task.checkCancellation()
        try await linkProviderIdentity()
        try Task.checkCancellation()
        try await verifyLinkedDestinationSession()
        try Task.checkCancellation()
        try await synchronizeStorePurchases()
        try Task.checkCancellation()
        try await completeServerHandoff()
        try Task.checkCancellation()
        guard try await refreshServerEntitlement() else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseContinuityPending
        }
        try Task.checkCancellation()
        try await verifyFinalDestinationSession()
        try Task.checkCancellation()
        try clearPendingHandoff()
    }
}
