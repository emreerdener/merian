import Foundation

/// Resumes every installed account-deletion recovery phase behind the same
/// injected Auth/session boundary used by fresh deletion intake.
@MainActor
struct AccountDeletionRecoveryCoordinator {
    private let dependencies: AccountDeletionCoordinationDependencies

    init(dependencies: AccountDeletionCoordinationDependencies) {
        self.dependencies = dependencies
    }

    func resumePendingLocalCleanup(
        requestDeletion: @MainActor @escaping (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt,
        recoverDeletion: @MainActor @escaping (
            String,
            Bool
        ) async throws -> AccountDeletionReceipt,
        recoverDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt,
        acknowledgeDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor @escaping () -> Void,
        purgeLocalData: @MainActor @escaping () -> Bool
    ) async -> Bool {
        guard let recoveryState = dependencies.localState.state() else {
            return true
        }
        let transitionKind: AuthTransitionKind = recoveryState.isIntakePending
            ? .accountDeletion
            : .accountDeletionCleanup
        guard let transition = dependencies.session.beginTransition(
            transitionKind
        ) else {
            return false
        }
        defer { dependencies.session.finishTransition(transition) }

        if recoveryState == .capabilityRejectionRetirementPending {
            let didRetireProof = AccountDeletionWorkflow
                .retireRejectedRecoveryProof(
                    retireRecoveryCapability: {
                        clearCapability(recoveryCapabilityStore)
                    }
                )
            guard didRetireProof else { return false }
            return await restoreDeferredCachedSessionAndResolveBarrier(
                ownedBy: transition
            )
        }

        if recoveryState == .capabilityRetirementPending {
            return await AccountDeletionWorkflow.performRecoveryRetirement(
                performLocalSignOut: {
                    await dependencies.session
                        .performVerifiedLocalSignOut(transition)
                },
                purgeLocalData: purgeLocalData,
                retireRecoveryCapability: {
                    clearCapability(recoveryCapabilityStore)
                },
                resolveCleanup: {
                    dependencies.localState.resolve()
                }
            )
        }

        let storedCapability: PreparedDeletionRecoveryCapability?
        do {
            storedCapability = try recoveryCapabilityStore
                .loadExistingIfPresent()
        } catch {
            return false
        }
        if let storedCapability,
           storedCapability.protocolVersion == 2 {
            return await resumeCapabilityBackedV2(
                transition: transition,
                recoveryState: recoveryState,
                capability: storedCapability,
                requestDeletionV1: requestDeletion,
                recoverDeletionV1: recoverDeletion,
                recoverDeletion: recoverDeletionV2,
                acknowledgeDeletion: acknowledgeDeletionV2,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData
            )
        }
        if storedCapability == nil,
           recoveryState == .capabilityLookupPending
            || recoveryState == .capabilityPreparationPending
            || recoveryState == .capabilityPreparedPending {
            return await restoreDeferredCachedSessionAndResolveBarrier(
                ownedBy: transition
            )
        }

        if recoveryState == .capabilityLookupPending {
            let capability: String?
            do {
                capability = try recoveryCapabilityStore
                    .loadExistingValueIfPresent()
            } catch {
                return false
            }
            guard capability != nil else {
                return await restoreDeferredCachedSessionAndResolveBarrier(
                    ownedBy: transition
                )
            }
            return await resumeCapabilityBackedV1(
                transition: transition,
                requestDeletion: requestDeletion,
                recoverDeletion: recoverDeletion,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData,
                allowAuthenticatedIntakeReplay: false
            )
        }

        if recoveryState.isIntakePending {
            if !recoveryState.requiresRecoveryCapability {
                // These installed states predate capability-backed intake or
                // carry a legacy proof. Keep the proof and endpoint on v1 so a
                // crash after an ambiguous request cannot relaunch into the v2
                // hash domain. A proofless prepared-v2 state was cancelled
                // above because destructive commit had not started.
                guard dependencies.session.currentCachedSession() != nil else {
                    return false
                }
                do {
                    _ = try recoveryCapabilityStore.prepareLegacyIntake()
                    guard dependencies.localState.recordIntakePending() else {
                        return false
                    }
                } catch {
                    return false
                }
            }
            return await resumeCapabilityBackedV1(
                transition: transition,
                requestDeletion: requestDeletion,
                recoverDeletion: recoverDeletion,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData,
                allowAuthenticatedIntakeReplay: true
            )
        }

        if recoveryState.requiresRecoveryCapability {
            return await resumeCapabilityBackedV1(
                transition: transition,
                requestDeletion: requestDeletion,
                recoverDeletion: recoverDeletion,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData,
                allowAuthenticatedIntakeReplay: false
            )
        }

        return await AccountDeletionWorkflow.performPendingLocalCleanup(
            performLocalSignOut: {
                await dependencies.session
                    .performVerifiedLocalSignOut(transition)
            },
            purgeLocalData: purgeLocalData,
            resolveCleanup: {
                dependencies.localState.resolve()
            }
        )
    }

    private func restoreDeferredCachedSessionAndResolveBarrier(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard dependencies.session.ownsTransition(transition),
              dependencies.localState.isPending(),
              let sourceSession = dependencies.session
                .sourceSession(transition) else {
            return false
        }

        let cachedSession: AccountDeletionCachedSession
        do {
            cachedSession = try await dependencies.session.loadCachedSession()
        } catch {
            return false
        }
        guard AccountDeletionTransitionPolicy.canRestoreDeferredBarrierSession(
            markerIsPending: dependencies.localState.isPending(),
            sourceSession: sourceSession,
            cachedUserID: cachedSession.identity.userID,
            cachedUserIsAnonymous: cachedSession.identity.isAnonymous,
            cachedSessionIsExpired: cachedSession.isExpired
        ), dependencies.session.ownsTransition(transition),
           dependencies.session.currentCachedSession()
            == cachedSession.identity else {
            return false
        }

        return AccountDeletionWorkflow.restoreDeferredBarrierSession(
            markerIsPending: {
                dependencies.localState.isPending()
            },
            adoptCachedSession: {
                guard dependencies.session.ownsTransition(transition),
                      dependencies.session.currentCachedSession()
                        == cachedSession.identity else {
                    return false
                }
                return dependencies.session.adoptCachedSession(
                    cachedSession.identity,
                    transition
                )
            },
            validateCachedSession: {
                dependencies.session.currentCachedSession()
                    == cachedSession.identity
                    && dependencies.session
                    .currentSessionMatchesTransition(transition)
            },
            resolveCleanup: {
                dependencies.localState.resolve()
            },
            publishCachedSession: {
                dependencies.session.publishCachedSession(
                    cachedSession.identity
                )
            }
        )
    }

    private func resumeCapabilityBackedV2(
        transition: AuthTransitionToken,
        recoveryState: AccountDeletionLocalRecoveryState,
        capability: PreparedDeletionRecoveryCapability,
        requestDeletionV1: @MainActor (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt,
        recoverDeletionV1: @MainActor (
            String,
            Bool
        ) async throws -> AccountDeletionReceipt,
        recoverDeletion: @MainActor (String) async throws
            -> AccountDeletionReceipt,
        acknowledgeDeletion: @MainActor (String) async throws
            -> AccountDeletionReceipt,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor () -> Void,
        purgeLocalData: @MainActor () -> Bool
    ) async -> Bool {
        guard capability.protocolVersion == 2,
              let acknowledgementCapability =
                capability.acknowledgementValue else {
            return false
        }

        dependencies.session.updateTransition(transition, .deletingAccount)
        let receipt: AccountDeletionReceipt
        do {
            receipt = try await recoverDeletion(capability.recoveryValue)
            guard dependencies.session
                .currentSessionMatchesTransition(transition),
                receipt.protocolVersion == 2 else {
                return false
            }
        } catch {
            guard dependencies.session
                .currentSessionMatchesTransition(transition) else {
                return false
            }
            if AccountDeletionTransitionPolicy.isUnknownRecovery(error) {
                if recoveryState == .capabilityIntakePending
                    || recoveryState == .capabilityCleanupPending {
                    // An earlier build could create a v2 envelope while
                    // upgrading a proofless legacy intake, then submit its
                    // recovery value to the v1 endpoint. A v2 404 is not
                    // definitive for that installed mixed state: ask the v1
                    // recovery route and retain both proof and barrier if it
                    // cannot produce a positive match.
                    return await resumeCapabilityBackedV1(
                        transition: transition,
                        requestDeletion: requestDeletionV1,
                        recoverDeletion: recoverDeletionV1,
                        recoveryCapabilityStore: recoveryCapabilityStore,
                        recordManualProviderRevocation:
                            recordManualProviderRevocation,
                        purgeLocalData: purgeLocalData,
                        allowAuthenticatedIntakeReplay: false
                    )
                }
                let didRetireProof = retireDefinitiveRejectionProof(
                    recoveryCapabilityStore
                )
                guard didRetireProof else { return false }
                return await restoreDeferredCachedSessionAndResolveBarrier(
                    ownedBy: transition
                )
            }
            if AccountDeletionTransitionPolicy.isAcceptedExpiredRecovery(
                error
            ) {
                receipt = AccountDeletionReceipt(
                    success: true,
                    status: .pending,
                    manualProviderRevocationRequired: true,
                    protocolVersion: 2
                )
            } else {
                return false
            }
        }

        if receipt.status == .notCommitted {
            let didRetireProof = retireDefinitiveRejectionProof(
                recoveryCapabilityStore
            )
            guard didRetireProof else { return false }
            return await restoreDeferredCachedSessionAndResolveBarrier(
                ownedBy: transition
            )
        }
        guard receipt.status == .pending || receipt.status == .completed else {
            return false
        }

        dependencies.session.updateTransition(transition, .finalizing)
        return await performAcceptedCleanup(
            receipt: receipt,
            transition: transition,
            recoveryCapabilityStore: recoveryCapabilityStore,
            recordManualProviderRevocation: recordManualProviderRevocation,
            purgeLocalData: purgeLocalData,
            acknowledgeRecovery: {
                let acknowledgement = try await acknowledgeDeletion(
                    acknowledgementCapability
                )
                return acknowledgement.recoveryAcknowledged == true
            }
        )
    }

    private func resumeCapabilityBackedV1(
        transition: AuthTransitionToken,
        requestDeletion: @MainActor (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt,
        recoverDeletion: @MainActor (
            String,
            Bool
        ) async throws -> AccountDeletionReceipt,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor () -> Void,
        purgeLocalData: @MainActor () -> Bool,
        allowAuthenticatedIntakeReplay: Bool
    ) async -> Bool {
        let capability: String
        do {
            capability = try recoveryCapabilityStore.loadExistingValue()
        } catch {
            dependencies.diagnostics.reportRecoveryProofUnavailable()
            return false
        }

        dependencies.session.updateTransition(transition, .deletingAccount)
        let receipt: AccountDeletionReceipt
        do {
            if allowAuthenticatedIntakeReplay,
               dependencies.localState.state()?.isIntakePending == true,
               dependencies.session.currentCachedSession() != nil {
                do {
                    try await dependencies.session
                        .verifyExpectedSession(transition)
                    receipt = try await requestDeletion(
                        transition,
                        capability
                    )
                } catch {
                    guard dependencies.session
                        .currentSessionMatchesTransition(transition) else {
                        return false
                    }
                    if AccountDeletionTransitionPolicy
                        .isDefinitiveIntakeRejection(error) {
                        let didRetireProof =
                            retireDefinitiveRejectionProof(
                                recoveryCapabilityStore
                            )
                        guard didRetireProof else { return false }
                        return await restoreDeferredCachedSessionAndResolveBarrier(
                            ownedBy: transition
                        )
                    }
                    receipt = try await recoverDeletion(capability, false)
                }
            } else {
                receipt = try await recoverDeletion(capability, false)
            }
            guard dependencies.session
                .currentSessionMatchesTransition(transition) else {
                return false
            }
        } catch {
            guard dependencies.session
                .currentSessionMatchesTransition(transition) else {
                return false
            }
            if AccountDeletionTransitionPolicy.isAcceptedExpiredRecovery(
                error
            ) {
                receipt = AccountDeletionReceipt(
                    success: true,
                    status: .pending,
                    manualProviderRevocationRequired: true
                )
            } else {
                dependencies.diagnostics
                    .reportCapabilityRecoveryPending(error)
                return false
            }
        }

        dependencies.session.updateTransition(transition, .finalizing)
        return await performAcceptedCleanup(
            receipt: receipt,
            transition: transition,
            recoveryCapabilityStore: recoveryCapabilityStore,
            recordManualProviderRevocation: recordManualProviderRevocation,
            purgeLocalData: purgeLocalData,
            acknowledgeRecovery: {
                let acknowledgement = try await recoverDeletion(
                    capability,
                    true
                )
                return acknowledgement.recoveryAcknowledged == true
            }
        )
    }

    private func performAcceptedCleanup(
        receipt: AccountDeletionReceipt,
        transition: AuthTransitionToken,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor () -> Void,
        purgeLocalData: @MainActor () -> Bool,
        acknowledgeRecovery: @MainActor () async throws -> Bool
    ) async -> Bool {
        await AccountDeletionWorkflow.performAcceptedCleanup(
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
                    let wasAcknowledged = try await acknowledgeRecovery()
                    return wasAcknowledged
                        && dependencies.session
                        .currentSessionMatchesTransition(transition)
                } catch {
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
    }

    private func retireDefinitiveRejectionProof(
        _ store: AccountDeletionRecoveryCapabilityStore
    ) -> Bool {
        AccountDeletionWorkflow.retireDefinitiveIntakeRejectionProof(
            recordRejectionRetirementPending: {
                dependencies.localState
                    .recordCapabilityRejectionRetirementPending()
            },
            retireRecoveryCapability: {
                clearCapability(store)
            }
        )
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
