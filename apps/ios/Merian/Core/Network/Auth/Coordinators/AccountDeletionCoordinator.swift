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
        purgeLocalData: @MainActor @escaping () -> Bool
    ) async throws -> AccountDeletionReceipt {
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
        try await dependencies.session.verifyExpectedSession(transition)
        try Task.checkCancellation()

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
                            dependencies.session
                                .currentSessionMatchesTransition(transition)
                        },
                        recordCapabilityPreparedPending: {
                            dependencies.localState
                                .recordCapabilityPreparedPending()
                        },
                        recordIntakePending: {
                            dependencies.localState.recordIntakePending()
                        },
                        commitDeletion: {
                            try await commitDeletionV2(
                                transition,
                                preparedCapability.recoveryValue
                            )
                        },
                        verifyCommitContext: {
                            dependencies.session
                                .currentSessionMatchesTransition(transition)
                        }
                    )
            } else {
                receipt = try await AccountDeletionWorkflow
                    .performDurableIntake(
                        recordIntakePending: {
                            dependencies.localState.recordIntakePending()
                        },
                        requestDeletion: {
                            try await requestDeletion(
                                transition,
                                preparedCapability.recoveryValue
                            )
                        },
                        verifyResultContext: {
                            guard dependencies.session
                                .currentSessionMatchesTransition(
                                    transition
                                ) else {
                                throw SupabaseAuthTransitionError
                                    .signOutSessionChanged
                            }
                        },
                        clearIntakeAfterDefinitiveRejection: {
                            _ = AccountDeletionWorkflow
                                .performDefinitiveIntakeRejectionRetirement(
                                    recordRejectionRetirementPending: {
                                        dependencies.localState
                                            .recordCapabilityRejectionRetirementPending()
                                    },
                                    retireRecoveryCapability: {
                                        clearCapability(
                                            recoveryCapabilityStore
                                        )
                                    },
                                    resolveCleanup: {
                                        dependencies.localState.resolve()
                                    }
                                )
                        }
                    )
            }
        } catch {
            if preparedCapability.protocolVersion == 2,
               AccountDeletionTransitionPolicy
                .isDefinitiveIntakeRejection(error),
               let cancellation = try? await recoverDeletionV2(
                   preparedCapability.recoveryValue
               ), dependencies.session.currentSessionMatchesTransition(
                   transition
               ), cancellation.status == .notCommitted {
                _ = AccountDeletionWorkflow
                    .performDefinitiveIntakeRejectionRetirement(
                        recordRejectionRetirementPending: {
                            dependencies.localState
                                .recordCapabilityRejectionRetirementPending()
                        },
                        retireRecoveryCapability: {
                            clearCapability(recoveryCapabilityStore)
                        },
                        resolveCleanup: {
                            dependencies.localState.resolve()
                        }
                    )
            }
            if preparedCapability.wasCreated,
               !dependencies.localState.isPending() {
                try? recoveryCapabilityStore.clearVerified()
            }
            throw error
        }

        dependencies.session.updateTransition(transition, .finalizing)
        let didPurge = await AccountDeletionWorkflow.performAcceptedCleanup(
            receipt: receipt,
            recordCleanupPending: {
                dependencies.localState.recordCleanupPending()
            },
            recordManualProviderRevocation: recordManualProviderRevocation,
            performLocalSignOut: {
                await dependencies.session
                    .performVerifiedLocalSignOut(transition)
            },
            purgeLocalData: purgeLocalData,
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
                        && dependencies.session
                        .currentSessionMatchesTransition(transition)
                } catch {
                    dependencies.diagnostics
                        .reportAcknowledgementPending(error)
                    return false
                }
            },
            recordRecoveryRetirementPending: {
                dependencies.localState
                    .recordCapabilityRetirementPending()
            },
            retireRecoveryCapability: {
                clearCapability(recoveryCapabilityStore)
            },
            resolveCleanup: {
                dependencies.localState.resolve()
            }
        )
        if !didPurge {
            dependencies.diagnostics.reportAcceptedCleanupPending()
        }
        return receipt
    }

    private func clearCapability(
        _ store: AccountDeletionRecoveryCapabilityStore
    ) -> Bool {
        do {
            try store.clearVerified()
            return true
        } catch {
            return false
        }
    }
}
