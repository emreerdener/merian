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
        purgeLocalData: @MainActor @escaping (AccountDeletionLocalCleanupStore.RecoveryScope) async -> Bool
    ) async -> Bool {
        guard !MerianEnvironment.isHistoryQualificationBuild else { return false }
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
                    retireRecoveryCapability: recoveryCapabilityStore.retireVerified
                )
            guard didRetireProof else { return false }
            return await restoreDeferredCachedSessionAndResolveBarrier(
                ownedBy: transition
            )
        }

        let storedCapability: PreparedDeletionRecoveryCapability?
        do {
            storedCapability = try recoveryCapabilityStore
                .loadExistingIfPresent()
        } catch {
            return false
        }
        if recoveryState == .capabilityRetirementPending {
            let scope = dependencies.scope(transition, state: recoveryState, proof: storedCapability, store: recoveryCapabilityStore)
            return await AccountDeletionWorkflow.performRecoveryRetirement(
                validateContext: { scope.isCurrent },
                performLocalSignOut: {
                    await dependencies.session
                        .performVerifiedLocalSignOut(transition, scope)
                },
                purgeLocalData: {
                    guard await purgeLocalData(scope), scope.isCurrent else { return false }
                    return dependencies.acknowledgeLibraryPurge(scope)
                },
                retireRecoveryCapability: recoveryCapabilityStore.retireVerified,
                resolveCleanup: dependencies.localState.resolve
            )
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

        let scope = dependencies.scope(transition, state: .cleanupPending, proof: storedCapability, store: recoveryCapabilityStore)
        return await AccountDeletionWorkflow.performPendingLocalCleanup(
            validateContext: { scope.isCurrent },
            performLocalSignOut: {
                await dependencies.session
                    .performVerifiedLocalSignOut(transition, scope)
            },
            purgeLocalData: {
                guard await purgeLocalData(scope), scope.isCurrent else { return false }
                return dependencies.acknowledgeLibraryPurge(scope)
            },
            resolveCleanup: dependencies.localState.resolve
        )
    }

    private func restoreDeferredCachedSessionAndResolveBarrier(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard dependencies.validateLibrary(nil), dependencies.session.ownsTransition(transition),
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
        ), dependencies.validateLibrary(nil), dependencies.session.ownsTransition(transition),
           dependencies.session.currentCachedSession()
            == cachedSession.identity else {
            return false
        }

        return AccountDeletionWorkflow.restoreDeferredBarrierSession(
            markerIsPending: {
                dependencies.localState.isPending()
            },
            adoptCachedSession: {
                guard dependencies.validateLibrary(nil), dependencies.session.ownsTransition(transition),
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
                    && dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition)
            },
            resolveCleanup: dependencies.localState.resolve,
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
        purgeLocalData: @MainActor (AccountDeletionLocalCleanupStore.RecoveryScope) async -> Bool
    ) async -> Bool {
        guard capability.protocolVersion == 2,
              let acknowledgementCapability =
                capability.acknowledgementValue else {
            return false
        }

        let contextIsCurrent = { dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition) &&
            dependencies.localState.state() == recoveryState && recoveryCapabilityStore.matchesExisting(capability) }
        dependencies.session.updateTransition(transition, .deletingAccount)
        let receipt: AccountDeletionReceipt
        do {
            receipt = try await recoverDeletion(capability.recoveryValue)
            guard contextIsCurrent(),
                receipt.protocolVersion == 2 else {
                return false
            }
        } catch {
            guard contextIsCurrent() else {
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
            expectedCapability: capability, expectedState: recoveryState,
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
        purgeLocalData: @MainActor (AccountDeletionLocalCleanupStore.RecoveryScope) async -> Bool,
        allowAuthenticatedIntakeReplay: Bool
    ) async -> Bool {
        let storedCapability: PreparedDeletionRecoveryCapability
        do {
            guard let stored = try recoveryCapabilityStore.loadExistingIfPresent() else { return false }
            storedCapability = stored
        } catch {
            dependencies.diagnostics.reportRecoveryProofUnavailable()
            return false
        }

        let capability = storedCapability.recoveryValue
        let recoveryState = dependencies.localState.state()
        let contextIsCurrent = { dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition) &&
            dependencies.localState.state() == recoveryState && recoveryCapabilityStore.matchesExisting(storedCapability) }
        dependencies.session.updateTransition(transition, .deletingAccount)
        let receipt: AccountDeletionReceipt
        do {
            if allowAuthenticatedIntakeReplay,
               dependencies.localState.state()?.isIntakePending == true,
               dependencies.session.currentCachedSession() != nil {
                do {
                    try await dependencies.session
                        .verifyExpectedSession(transition, dependencies.scope(transition, state: recoveryState, proof: storedCapability, store: recoveryCapabilityStore))
                    guard contextIsCurrent() else { return false }
                    receipt = try await requestDeletion(
                        transition,
                        capability
                    )
                } catch {
                    guard contextIsCurrent() else {
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
            guard contextIsCurrent() else {
                return false
            }
        } catch {
            guard contextIsCurrent() else {
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
            expectedCapability: storedCapability, expectedState: recoveryState,
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
        expectedCapability: PreparedDeletionRecoveryCapability, expectedState: AccountDeletionLocalRecoveryState?,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor () -> Void,
        purgeLocalData: @MainActor (AccountDeletionLocalCleanupStore.RecoveryScope) async -> Bool,
        acknowledgeRecovery: @MainActor () async throws -> Bool
    ) async -> Bool {
        let scope = dependencies.scope(transition, state: .capabilityCleanupPending, proof: expectedCapability, store: recoveryCapabilityStore)
        return await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { scope.isCurrent },
            receipt: receipt,
            recordCleanupPending: {
                dependencies.localState.state() == expectedState && recoveryCapabilityStore.matchesExisting(expectedCapability) &&
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
                    let wasAcknowledged = try await acknowledgeRecovery()
                    return wasAcknowledged
                        && dependencies.validateLibrary(nil) && dependencies.session.currentSessionMatchesTransition(transition)
                } catch {
                    return false
                }
            },
            recordRecoveryRetirementPending: dependencies.localState.recordCapabilityRetirementPending,
            retireRecoveryCapability: recoveryCapabilityStore.retireVerified,
            resolveCleanup: dependencies.localState.resolve
        )
    }

    private func retireDefinitiveRejectionProof(
        _ store: AccountDeletionRecoveryCapabilityStore
    ) -> Bool {
        AccountDeletionWorkflow.retireDefinitiveIntakeRejectionProof(
            recordRejectionRetirementPending: dependencies.localState.recordCapabilityRejectionRetirementPending,
            retireRecoveryCapability: store.retireVerified
        )
    }

}
