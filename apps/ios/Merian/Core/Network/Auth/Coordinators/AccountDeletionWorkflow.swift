@MainActor
enum AccountDeletionWorkflow {
    /// The transition coordinator must adopt the exact cached source before
    /// the durable deletion barrier is removed. The adopted SDK session is
    /// revalidated immediately before marker removal, and observable account
    /// state is then published without another failable step. Because every
    /// closure is synchronous on MainActor, ordinary account work cannot enter
    /// between these steps.
    static func restoreDeferredBarrierSession(
        markerIsPending: @MainActor () -> Bool,
        adoptCachedSession: @MainActor () -> Bool,
        validateCachedSession: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool,
        publishCachedSession: @MainActor () -> Void
    ) -> Bool {
        guard markerIsPending(),
              adoptCachedSession(),
              validateCachedSession(),
              resolveCleanup(),
              !markerIsPending() else {
            return false
        }
        publishCachedSession()
        return true
    }

    /// Persists an identity-free intent before the first network suspension.
    /// A lost response therefore replays the server's idempotent intake instead
    /// of restoring the cached account. Only the received, definitive
    /// `409 purchase_continuity_pending` response may retire the intent without
    /// a server receipt; every ambiguous outcome stays fenced for foreground or
    /// cold-launch recovery.
    static func performDurableIntake(
        recordIntakePending: @MainActor () -> Bool,
        requestDeletion: @MainActor () async throws -> AccountDeletionReceipt,
        verifyResultContext: @MainActor () throws -> Void,
        clearIntakeAfterDefinitiveRejection: @MainActor () -> Void
    ) async throws -> AccountDeletionReceipt {
        try Task.checkCancellation()
        guard recordIntakePending() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }
        // A synchronous persistence adapter may surface cancellation after it
        // has durably closed account work. Preserve that recovery marker, but
        // do not dispatch destructive intake from an already-cancelled task.
        try Task.checkCancellation()
        let receipt: AccountDeletionReceipt
        do {
            receipt = try await requestDeletion()
        } catch {
            try verifyResultContext()
            if AccountDeletionTransitionPolicy
                .isDefinitiveIntakeRejection(error) {
                clearIntakeAfterDefinitiveRejection()
            }
            throw error
        }
        try verifyResultContext()
        return receipt
    }

    /// Promotes a non-destructive protocol-v2 preparation into destructive
    /// intake only after both recovery markers are durably persisted. Thrown
    /// preparation and commit results are context-checked before they can
    /// reach the caller's recovery classifier.
    static func performPreparedIntake(
        prepareDeletion: @MainActor () async throws
            -> AccountDeletionPreparationReceipt,
        verifyPreparationContext: @MainActor () -> Bool,
        recordCapabilityPreparedPending: @MainActor () -> Bool,
        recordIntakePending: @MainActor () -> Bool,
        commitDeletion: @MainActor () async throws
            -> AccountDeletionReceipt,
        verifyCommitContext: @MainActor () -> Bool
    ) async throws -> AccountDeletionReceipt {
        try Task.checkCancellation()
        let preparation: AccountDeletionPreparationReceipt
        do {
            preparation = try await prepareDeletion()
        } catch {
            guard verifyPreparationContext() else {
                throw SupabaseAuthTransitionError
                    .accountDeletionRecoveryPersistenceFailed
            }
            throw error
        }
        guard verifyPreparationContext() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }
        // Preparation is non-destructive. If its request ignored caller
        // cancellation, retain the already-persisted capability for recovery
        // instead of promoting the cancelled operation into commit.
        try Task.checkCancellation()
        guard preparation.status == .prepared,
              preparation.protocolVersion == 2,
              recordCapabilityPreparedPending(),
              recordIntakePending() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }
        // The two durable markers are now authoritative. A persistence adapter
        // that cancelled the task leaves them available for recovery; it must
        // not allow the destructive request to start in this task generation.
        try Task.checkCancellation()

        let receipt: AccountDeletionReceipt
        do {
            receipt = try await commitDeletion()
        } catch {
            guard verifyCommitContext() else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            throw error
        }
        guard verifyCommitContext(),
              receipt.protocolVersion == 2,
              receipt.status == .pending || receipt.status == .completed else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        return receipt
    }

    /// Once the server accepts deletion, record recovery state before the next
    /// suspension. A terminated task can then finish local erasure on launch.
    static func performAcceptedCleanup(
        receipt: AccountDeletionReceipt,
        recordCleanupPending: @MainActor () -> Bool,
        recordManualProviderRevocation: @MainActor () -> Void,
        performLocalSignOut: @MainActor () async -> Bool,
        purgeLocalData: @MainActor () -> Bool,
        acknowledgeRecovery: @MainActor () async -> Bool,
        recordRecoveryRetirementPending: @MainActor () -> Bool,
        retireRecoveryCapability: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) async -> Bool {
        guard receipt.success,
              receipt.status == .pending || receipt.status == .completed,
              recordCleanupPending() else {
            return false
        }
        if receipt.manualProviderRevocationRequired {
            recordManualProviderRevocation()
        }
        guard await performLocalSignOut() else { return false }
        guard purgeLocalData() else { return false }
        guard await acknowledgeRecovery() else { return false }
        guard recordRecoveryRetirementPending() else { return false }
        guard retireRecoveryCapability() else { return false }
        return resolveCleanup()
    }

    static func performRecoveryRetirement(
        performLocalSignOut: @MainActor () async -> Bool,
        purgeLocalData: @MainActor () -> Bool,
        retireRecoveryCapability: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) async -> Bool {
        guard await performLocalSignOut() else { return false }
        guard purgeLocalData() else { return false }
        guard retireRecoveryCapability() else { return false }
        return resolveCleanup()
    }

    /// A definitive pre-commit rejection authorizes retirement of the unused
    /// proof only. Keeping this separate from accepted-deletion retirement is
    /// what prevents a crash from turning a rejected request into local data
    /// erasure on the next launch.
    static func retireRejectedRecoveryProof(
        retireRecoveryCapability: @MainActor () -> Bool
    ) -> Bool {
        retireRecoveryCapability()
    }

    /// A definitive intake rejection can retire the unused recovery proof, but
    /// the retirement phase must reach durable storage first. If the process is
    /// terminated after proof deletion and before marker removal, launch can
    /// then finish the proof-only cleanup instead of treating the absent proof
    /// as an ambiguous accepted deletion.
    static func retireDefinitiveIntakeRejectionProof(
        recordRejectionRetirementPending: @MainActor () -> Bool,
        retireRecoveryCapability: @MainActor () -> Bool
    ) -> Bool {
        guard recordRejectionRetirementPending() else { return false }
        return retireRejectedRecoveryProof(
            retireRecoveryCapability: retireRecoveryCapability
        )
    }

    static func performDefinitiveIntakeRejectionRetirement(
        recordRejectionRetirementPending: @MainActor () -> Bool,
        retireRecoveryCapability: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) -> Bool {
        guard retireDefinitiveIntakeRejectionProof(
            recordRejectionRetirementPending:
                recordRejectionRetirementPending,
            retireRecoveryCapability: retireRecoveryCapability
        ) else { return false }
        return resolveCleanup()
    }

    static func performPendingLocalCleanup(
        performLocalSignOut: @MainActor () async -> Bool,
        purgeLocalData: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) async -> Bool {
        guard await performLocalSignOut() else { return false }
        guard purgeLocalData() else { return false }
        return resolveCleanup()
    }
}
