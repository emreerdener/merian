import Foundation

/// Sequences authenticated deletion intake and accepted local cleanup through
/// narrow, injected live boundaries. Durable phase order remains in
/// `AccountDeletionWorkflow`; this owner binds that policy to the exact Auth
/// transition without acquiring a client or store singleton, or creating a
/// task.
@MainActor
struct AccountDeletionCoordinator {
    private let dependencies: AccountDeletionCoordinationDependencies

    init(dependencies: AccountDeletionCoordinationDependencies) {
        self.dependencies = dependencies
    }

    func deleteCurrentAccount(
        prepareDeletionV2: @MainActor @escaping (
            AuthTransitionToken,
            String,
            String
        ) async throws -> AccountDeletionPreparationReceipt,
        commitDeletionV2: @MainActor @escaping (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt,
        recoverDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt,
        requestDeletion: @MainActor @escaping (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt,
        acknowledgeDeletion: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt,
        acknowledgeDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor @escaping () -> Void,
        purgeLocalData: @MainActor @escaping (AccountDeletionLocalCleanupStore.RecoveryScope) async -> Bool
    ) async throws -> AccountDeletionReceipt {
        try MerianEnvironment.requireQualificationDeletionPermission()
        try Task.checkCancellation()
        guard !dependencies.hasPendingPurchaseIdentityHandoff() else {
            throw SupabaseAuthTransitionError.signOutPurchaseContinuityPending
        }
        guard !dependencies.localState.isPending() else {
            throw SupabaseAuthTransitionError.accountDeletionRecoveryPending
        }
        guard let transition = dependencies.session.beginTransition(
            .accountDeletion
        ) else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }
        defer { dependencies.session.finishTransition(transition) }

        dependencies.session.updateTransition(transition, .deletingAccount)
        try await dependencies.session.verifyExpectedSession(transition, dependencies.scope(transition, state: nil,
            proof: try recoveryCapabilityStore.loadExistingIfPresent(), store: recoveryCapabilityStore))
        try Task.checkCancellation()
        guard !dependencies.localState.isPending() else { throw SupabaseAuthTransitionError.accountDeletionRecoveryPending }

        guard dependencies.localState
            .recordCapabilityPreparationPending() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }
        let preparedCapability = try recoveryCapabilityStore.prepare()

        let receipt: AccountDeletionReceipt
        do {
            if preparedCapability.supportsPreparedCommit,
               let acknowledgementCapability =
                preparedCapability.acknowledgementValue {
                receipt = try await AccountDeletionWorkflow
                    .performPreparedIntake(
                        prepareDeletion: {
                            try await prepareDeletionV2(
                                transition,
                                preparedCapability.recoveryValue,
                                acknowledgementCapability
                            )
                        },
                        verifyPreparationContext: {
                            dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition) &&
                                dependencies.localState.state() == .capabilityPreparationPending && recoveryCapabilityStore.matchesExisting(preparedCapability)
                        },
                        recordCapabilityPreparedPending: dependencies.localState.recordCapabilityPreparedPending,
                        recordIntakePending: dependencies.localState.recordIntakePending,
                        commitDeletion: {
                            try await commitDeletionV2(
                                transition,
                                preparedCapability.recoveryValue
                            )
                        },
                        verifyCommitContext: {
                            dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition) &&
                                dependencies.localState.state() == .capabilityIntakePending && recoveryCapabilityStore.matchesExisting(preparedCapability)
                        }
                    )
            } else {
                receipt = try await AccountDeletionWorkflow
                    .performDurableIntake(
                        recordIntakePending: dependencies.localState.recordIntakePending,
                        requestDeletion: {
                            try await requestDeletion(
                                transition,
                                preparedCapability.recoveryValue
                            )
                        },
                        verifyResultContext: {
                            guard dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition), dependencies.localState.state() == .capabilityIntakePending,
                                  recoveryCapabilityStore.matchesExisting(preparedCapability) else {
                                throw SupabaseAuthTransitionError
                                    .signOutSessionChanged
                            }
                        },
                        clearIntakeAfterDefinitiveRejection: {
                            _ = AccountDeletionWorkflow
                                .performDefinitiveIntakeRejectionRetirement(
                                    recordRejectionRetirementPending: dependencies.localState.recordCapabilityRejectionRetirementPending,
                                    retireRecoveryCapability: recoveryCapabilityStore.retireVerified,
                                    resolveCleanup: dependencies.localState.resolve
                                )
                        }
                    )
            }
        } catch {
            let failedState = dependencies.localState.state()
            if preparedCapability.protocolVersion == 2,
               dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition), recoveryCapabilityStore.matchesExisting(preparedCapability),
               failedState == .capabilityPreparationPending || failedState == .capabilityIntakePending,
               AccountDeletionTransitionPolicy
                .isDefinitiveIntakeRejection(error),
               let cancellation = try? await recoverDeletionV2(
                   preparedCapability.recoveryValue
               ), dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition), dependencies.localState.state() == failedState, recoveryCapabilityStore.matchesExisting(preparedCapability),
               cancellation.status == .notCommitted {
                _ = AccountDeletionWorkflow
                    .performDefinitiveIntakeRejectionRetirement(
                        recordRejectionRetirementPending: dependencies.localState.recordCapabilityRejectionRetirementPending,
                        retireRecoveryCapability: recoveryCapabilityStore.retireVerified,
                        resolveCleanup: dependencies.localState.resolve
                    )
            }
            if preparedCapability.wasCreated,
               !dependencies.localState.isPending(), recoveryCapabilityStore.matchesExisting(preparedCapability) {
                try? recoveryCapabilityStore.clearVerified()
            }
            throw error
        }

        dependencies.session.updateTransition(transition, .finalizing)
        let scope = dependencies.scope(transition, state: .capabilityCleanupPending, proof: preparedCapability, store: recoveryCapabilityStore)
        let didPurge = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { scope.isCurrent },
            receipt: receipt,
            recordCleanupPending: {
                dependencies.localState.state() == .capabilityIntakePending && recoveryCapabilityStore.matchesExisting(preparedCapability) &&
                    dependencies.localState.recordCleanupPending()
            },
            recordManualProviderRevocation: recordManualProviderRevocation,
            performLocalSignOut: {
                await dependencies.session
                    .performVerifiedLocalSignOut(transition, scope)
            },
            purgeLocalData: {
                guard await purgeLocalData(scope), scope.isCurrent else { return false }
                return dependencies.acknowledgeLibraryPurge(scope)
            },
            acknowledgeRecovery: {
                do {
                    let acknowledgement: AccountDeletionReceipt
                    if preparedCapability.protocolVersion == 2,
                       let acknowledgementCapability =
                        preparedCapability.acknowledgementValue {
                        acknowledgement = try await acknowledgeDeletionV2(
                            acknowledgementCapability
                        )
                    } else {
                        acknowledgement = try await acknowledgeDeletion(
                            preparedCapability.recoveryValue
                        )
                    }
                    return acknowledgement.recoveryAcknowledged == true
                        && dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition)
                } catch {
                    dependencies.diagnostics
                        .reportAcknowledgementPending(error)
                    return false
                }
            },
            recordRecoveryRetirementPending: dependencies.localState.recordCapabilityRetirementPending,
            retireRecoveryCapability: recoveryCapabilityStore.retireVerified,
            resolveCleanup: dependencies.localState.resolve
        )
        if !didPurge {
            dependencies.diagnostics.reportAcceptedCleanupPending()
        }
        return receipt
    }

}
