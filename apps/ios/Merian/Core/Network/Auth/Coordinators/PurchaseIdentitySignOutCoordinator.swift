import Foundation

/// Routes ordinary, stable-principal, and compatibility sign-out through one
/// exact-session transition. Live SDK, provider, journal, and logging effects
/// are supplied by the Auth facade through narrow closure boundaries.
@MainActor
struct PurchaseIdentitySignOutCoordinator {
    private let dependencies: PurchaseSignOutDependencies

    init(dependencies: PurchaseSignOutDependencies) {
        self.dependencies = dependencies
    }

    func transitionToGhostSession() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard let transition = dependencies.session.beginTransition(.signOut)
        else {
            return false
        }
        defer { dependencies.session.finishTransition(transition) }
        return await performTransition(ownedBy: transition)
    }

    func resetGhostSessionForRetry(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              transition.kind == .recovery else { return false }
        return await performTransition(ownedBy: transition)
    }

    func retryPendingHandoff() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard let transition = dependencies.session.beginTransition(.recovery)
        else {
            return false
        }
        defer { dependencies.session.finishTransition(transition) }

        guard await dependencies.session.awaitAccountBoundWorkQuiescence(),
              !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        guard let session = try? await dependencies.session.loadSDKSession(),
              session.identity.isAnonymous,
              !Task.isCancelled,
              dependencies.session.currentSessionMatchesTransition(
                  transition
              ) else {
            return false
        }
        dependencies.session.updateTransition(
            transition,
            .bindingPurchases
        )
        return await dependencies.journal.completePendingHandoff(
            session.identity.userID.uuidString,
            transition
        )
    }

    private func performTransition(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        guard await dependencies.session.awaitAccountBoundWorkQuiescence()
        else {
            return false
        }
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }

        let pendingLegacyHandoff: PendingSignOutPurchaseHandoff?
        let pendingStableRotation: PendingPurchasePrincipalAuthRotation?
        do {
            pendingLegacyHandoff = try dependencies.journal
                .loadLegacyHandoff()
            pendingStableRotation = try dependencies.journal
                .loadStableRotation()
        } catch {
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportUnreadableJournal()
            return false
        }

        let startingSession: PurchaseIdentitySignOutSessionSnapshot?
        do {
            startingSession = try await dependencies.session.loadSDKSession()
        } catch {
            guard !dependencies.session.hasKnownLinkedIdentity() else {
                dependencies.diagnostics.reportUnverifiedLinkedSession()
                return false
            }
            startingSession = dependencies.session.fallbackPublishedSession()
        }
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }

        if let pendingStableRotation {
            guard await resolvePendingStableRotation(
                pendingStableRotation,
                legacyHandoffIsPending: pendingLegacyHandoff != nil,
                startingSession: startingSession,
                ownedBy: transition
            ) else {
                return false
            }
            if startingSession?.identity.isAnonymous == true
                || startingSession == nil {
                return true
            }
        }

        if let pendingLegacyHandoff {
            guard await resolvePendingLegacyHandoff(
                pendingLegacyHandoff,
                startingSession: startingSession,
                ownedBy: transition
            ) else {
                return false
            }
            if startingSession?.identity.isAnonymous == true
                || startingSession == nil {
                return true
            }
        }

        guard let startingSession,
              !startingSession.identity.isAnonymous else {
            return await PurchaseIdentitySignOutWorkflow
                .performUserSignOutTransition(
                    performSignOut: {
                        await dependencies.session.performLocalSignOut(
                            transition
                        )
                    },
                    initializeAnonymousSession: {
                        await dependencies.session
                            .initializeAnonymousSession(transition)?
                            .isAnonymous == true
                    }
                )
        }

        guard let source = await dependencies.session
            .resolveLinkedSourceContext(startingSession, transition) else {
            return false
        }
        return await performPurchaseSafeTransition(
            source: source,
            ownedBy: transition
        )
    }

    private func resolvePendingStableRotation(
        _ pending: PendingPurchasePrincipalAuthRotation,
        legacyHandoffIsPending: Bool,
        startingSession: PurchaseIdentitySignOutSessionSnapshot?,
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        dependencies.journal.setHandoffPending(true)
        if let startingSession, startingSession.identity.isAnonymous {
            return await dependencies.journal.completePendingHandoff(
                startingSession.identity.userID.uuidString,
                transition
            )
        }
        guard let startingSession else {
            return await initializeAnonymousSessionAndCompletePendingHandoff(
                ownedBy: transition
            )
        }
        guard startingSession.identity.userID.uuidString.caseInsensitiveCompare(
            pending.sourceUserId
        ) == .orderedSame else {
            dependencies.diagnostics.reportUnrelatedStableRotation()
            return false
        }

        await dependencies.journal
            .abandonStableRotationIfSourceRestored(
                startingSession.identity.userID,
                transition
            )
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        do {
            guard try dependencies.journal.loadStableRotation() == nil else {
                return false
            }
            dependencies.journal.setHandoffPending(
                legacyHandoffIsPending
            )
            return true
        } catch {
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportUnreadableJournal()
            return false
        }
    }

    private func resolvePendingLegacyHandoff(
        _ pending: PendingSignOutPurchaseHandoff,
        startingSession: PurchaseIdentitySignOutSessionSnapshot?,
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        dependencies.journal.setHandoffPending(true)
        if let startingSession, startingSession.identity.isAnonymous {
            return await dependencies.journal.completePendingHandoff(
                startingSession.identity.userID.uuidString,
                transition
            )
        }
        guard let startingSession else {
            return await initializeAnonymousSessionAndCompletePendingHandoff(
                ownedBy: transition
            )
        }
        guard startingSession.identity.userID.uuidString.caseInsensitiveCompare(
            pending.sourceUserId
        ) == .orderedSame else {
            dependencies.diagnostics.reportUnrelatedLegacyHandoff()
            return false
        }

        await dependencies.journal
            .abandonLegacyHandoffIfSourceRestored(
                pending.sourceUserId,
                transition
            )
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        do {
            guard try dependencies.journal.loadLegacyHandoff() == nil else {
                return false
            }
            return true
        } catch {
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportUnreadableJournal()
            return false
        }
    }

    private func performPurchaseSafeTransition(
        source: PurchaseIdentitySignOutSourceContext,
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition) else {
            return false
        }
        if source.binding.mode == .stable,
           !source.purchaseProviderIsReady {
            return false
        }
        dependencies.journal.setHandoffPending(true)

        let completed = await PurchaseIdentitySignOutWorkflow
            .performPurchaseSafeSignOutTransition(
                prepareAndPersistHandoff: {
                    switch source.binding.mode {
                    case .stable:
                        try await dependencies.journal
                            .prepareStableRotation(source, transition)
                    case .legacy:
                        try await dependencies.journal
                            .prepareLegacyHandoff(
                                source.session.userID.uuidString.lowercased(),
                                transition
                            )
                    }
                },
                performSignOut: {
                    await dependencies.session.performLocalSignOut(transition)
                },
                initializeAnonymousSession: {
                    await dependencies.session
                        .initializeAnonymousSession(transition)?
                        .isAnonymous == true
                },
                completeHandoff: {
                    guard await dependencies.journal.completePendingHandoff(
                        nil,
                        transition
                    ) else {
                        throw SupabaseAuthTransitionError
                            .signOutPurchaseContinuityPending
                    }
                },
                reportFailure: dependencies.diagnostics
                    .reportTransitionFailure
            )

        if !completed {
            switch source.binding.mode {
            case .stable:
                await dependencies.journal
                    .abandonStableRotationIfSourceRestored(
                        source.session.userID,
                        transition
                    )
            case .legacy:
                await dependencies.journal
                    .abandonLegacyHandoffIfSourceRestored(
                        source.session.userID.uuidString.lowercased(),
                        transition
                    )
            }
            await dependencies.journal
                .restoreSourceIdentityAfterFailedSignOut(
                    source.session.userID,
                    transition
                )
        }
        return completed
    }

    private func initializeAnonymousSessionAndCompletePendingHandoff(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard let destination = await dependencies.session
            .initializeAnonymousSession(transition),
              !Task.isCancelled,
              dependencies.session.ownsTransition(transition),
              dependencies.session.currentSessionMatchesTransition(
                  transition
              ),
              destination.isAnonymous else {
            return false
        }
        return await dependencies.journal.completePendingHandoff(
            destination.userID.uuidString,
            transition
        )
    }
}
