import Foundation

/// Owns source-side purchase-continuity preparation, restored-source proof
/// retirement, and failed-sign-out restoration. It creates no task and obtains
/// every SDK, store, provider, entitlement, and logging effect through narrow
/// dependencies.
@MainActor
struct PurchaseIdentitySourceHandoffCoordinator {
    private struct PendingState {
        let legacy: PendingSignOutPurchaseHandoff?
        let stable: PendingPurchasePrincipalAuthRotation?

        var isPending: Bool {
            legacy != nil || stable != nil
        }
    }

    private enum SourceOperation {
        case transition(AuthTransitionToken)
        case accountWork(AccountBoundWorkLease)
    }

    let dependencies: SourceHandoffDependencies

    func hasPendingHandoff() throws -> Bool {
        try loadPendingState().isPending
    }

    @discardableResult
    func loadAndPublishPendingState() throws -> Bool {
        let pending = try hasPendingHandoff()
        dependencies.journal.setHandoffPending(pending)
        return pending
    }

    func hasPendingHandoffFailClosed() -> Bool {
        do {
            return try loadAndPublishPendingState()
        } catch {
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportPendingStateFailure(error)
            return true
        }
    }

    func prepareStableRotation(
        source: PurchaseIdentitySignOutSourceContext,
        ownedBy transition: AuthTransitionToken
    ) async throws {
        guard dependencies.session.currentSessionMatchesTransition(
            transition
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let verified = try await dependencies.session.loadSDKSession()
        try Task.checkCancellation()
        guard sourceSessionIsCurrent(
            verified,
            source: source,
            transition: transition
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }

        do {
            try await dependencies.operations.prepareStableRotation(
                source.session.userID,
                source.binding
            )
        } catch PurchaseHandoffPreparationError.invalidStableBinding {
            throw SupabaseAuthTransitionError
                .purchasePrincipalRotationPersistenceFailed
        }

        let reverified = try await dependencies.session.loadSDKSession()
        try Task.checkCancellation()
        guard sourceSessionIsCurrent(
            reverified,
            source: source,
            transition: transition
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
    }

    func prepareLegacyHandoff(
        sourceUserID: String,
        ownedBy transition: AuthTransitionToken
    ) async throws {
        let normalizedSourceUserID = sourceUserID.lowercased()
        guard let sourceUUID = UUID(uuidString: normalizedSourceUserID),
              dependencies.session.currentSessionMatchesTransition(
                  transition
              ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let startingSession = try await dependencies.session.loadSDKSession()
        try Task.checkCancellation()
        guard !startingSession.isAnonymous,
              startingSession.userID == sourceUUID,
              dependencies.session.currentSessionMatchesTransition(
                  transition
              ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }

        do {
            try await dependencies.operations.prepareLegacyHandoff(sourceUUID)
        } catch LegacyPurchaseHandoffRemoteError.invalidResponse {
            throw SupabaseAuthTransitionError
                .signOutPurchaseHandoffPersistenceFailed
        }

        let verifiedSession = try await dependencies.session.loadSDKSession()
        try Task.checkCancellation()
        guard dependencies.session.currentSessionMatchesTransition(transition),
              !verifiedSession.isAnonymous,
              verifiedSession.userID == sourceUUID else {
            // Durable proof remains available if another session transition
            // already reached the anonymous destination.
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        dependencies.diagnostics.reportLegacyPreparation()
    }

    func abandonStableRotationIfSourceRestored(
        sourceUserID: UUID,
        ownedBy transition: AuthTransitionToken? = nil
    ) async {
        guard !Task.isCancelled,
              let operation = beginSourceOperation(
                  sourceUserID: sourceUserID,
                  transition: transition
              ) else {
            return
        }
        defer { finishSourceOperation(operation) }

        guard let session = try? await dependencies.session.loadSDKSession(),
              sourceOperationIsCurrent(operation),
              !Task.isCancelled,
              !session.isAnonymous,
              session.userID == sourceUserID else {
            return
        }
        do {
            if let pending = try dependencies.journal.loadStableRotation(),
               pending.sourceUserId.caseInsensitiveCompare(
                   sourceUserID.uuidString
               ) == .orderedSame {
                if case let .server(rotation) = pending {
                    try await dependencies.operations
                        .cancelStableRotation(rotation)
                }
                guard sourceOperationIsCurrent(operation),
                      !Task.isCancelled,
                      dependencies.session.currentSDKUserID()
                        == sourceUserID,
                      let reverified = try? await dependencies.session
                        .loadSDKSession(),
                      sourceOperationIsCurrent(operation),
                      !Task.isCancelled,
                      !reverified.isAnonymous,
                      reverified.userID == sourceUserID else {
                    dependencies.journal.setHandoffPending(true)
                    return
                }
                try dependencies.journal.clearStableRotation()
            }
            try loadAndPublishPendingState()
        } catch {
            dependencies.journal.setHandoffPending(true)
        }
    }

    func abandonLegacyHandoffIfSourceRestored(
        sourceUserID: String,
        ownedBy transition: AuthTransitionToken? = nil
    ) async {
        let normalizedSourceUserID = sourceUserID.lowercased()
        guard !Task.isCancelled,
              let sourceUUID = UUID(uuidString: normalizedSourceUserID),
              let operation = beginSourceOperation(
                  sourceUserID: sourceUUID,
                  transition: transition
              ) else {
            return
        }
        defer { finishSourceOperation(operation) }

        guard let session = try? await dependencies.session.loadSDKSession(),
              sourceOperationIsCurrent(operation),
              !Task.isCancelled,
              !session.isAnonymous,
              session.userID == sourceUUID else {
            return
        }

        do {
            guard let pending = try dependencies.journal
                .loadLegacyHandoff() else {
                try loadAndPublishPendingState()
                return
            }
            guard pending.sourceUserId.caseInsensitiveCompare(
                normalizedSourceUserID
            ) == .orderedSame else {
                return
            }
            try await dependencies.operations.cancelLegacyHandoff(pending)
            guard sourceOperationIsCurrent(operation),
                  !Task.isCancelled,
                  dependencies.session.currentSDKUserID() == sourceUUID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            try dependencies.journal.clearLegacyHandoff()
            try loadAndPublishPendingState()
            dependencies.diagnostics.reportLegacyAbandonment()
        } catch {
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics
                .reportLegacyAbandonmentFailure(error)
        }
    }

    func restoreSourceIdentityAfterFailedSignOut(
        sourceUserID: UUID,
        ownedBy transition: AuthTransitionToken
    ) async {
        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition),
              let session = try? await dependencies.session.loadSDKSession()
        else {
            return
        }
        guard !Task.isCancelled else { return }

        let purchaseContinuityPending: Bool
        do {
            purchaseContinuityPending = try hasPendingHandoff()
        } catch {
            dependencies.journal.setHandoffPending(true)
            return
        }
        guard AuthTransitionPolicy
            .shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: session.userID,
                activeUserIsAnonymous: session.isAnonymous,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: purchaseContinuityPending
            ) else {
            if purchaseContinuityPending {
                dependencies.journal.setHandoffPending(true)
            }
            return
        }

        guard !Task.isCancelled,
              dependencies.session.ownsTransition(transition),
              dependencies.session.adoptSourceSession(
                  sourceUserID,
                  transition
              ),
              dependencies.session.currentSessionMatchesTransition(
                  transition
              ) else {
            return
        }
        dependencies.journal.setHandoffPending(false)
        guard dependencies.session.publishRestoredSource(sourceUserID) else {
            return
        }

        await dependencies.operations.ensurePurchaseIdentityReady(
            sourceUserID,
            transition
        )
        guard !Task.isCancelled,
              dependencies.session.restoredSourceIsCurrent(
                  sourceUserID,
                  transition
              ) else {
            return
        }
        await dependencies.operations.beginEntitlementSession(
            sourceUserID,
            transition
        )
        guard dependencies.session.currentSessionMatchesTransition(
            transition
        ) else {
            return
        }
        dependencies.diagnostics.reportSourceRestoration()
    }

    private func loadPendingState() throws -> PendingState {
        let legacy = try dependencies.journal.loadLegacyHandoff()
        let stable = try dependencies.journal.loadStableRotation()
        return PendingState(legacy: legacy, stable: stable)
    }

    private func sourceSessionIsCurrent(
        _ session: AuthTransitionSession,
        source: PurchaseIdentitySignOutSourceContext,
        transition: AuthTransitionToken
    ) -> Bool {
        dependencies.session.currentSessionMatchesTransition(transition)
            && !session.isAnonymous
            && session.userID == source.session.userID
            && dependencies.session.currentPublishedUserID()
                == source.session.userID
            && dependencies.session.currentAuthGeneration()
                == source.authGeneration
    }

    private func beginSourceOperation(
        sourceUserID: UUID,
        transition: AuthTransitionToken?
    ) -> SourceOperation? {
        if let transition {
            guard dependencies.session.ownsTransition(transition),
                  dependencies.session.currentSessionMatchesTransition(
                      transition
                  ),
                  dependencies.session.currentSDKUserID() == sourceUserID
            else {
                return nil
            }
            return .transition(transition)
        }
        guard let lease = dependencies.session.beginUnownedAccountWork(
            sourceUserID
        ) else {
            return nil
        }
        return .accountWork(lease)
    }

    private func sourceOperationIsCurrent(
        _ operation: SourceOperation
    ) -> Bool {
        switch operation {
        case let .transition(transition):
            dependencies.session.currentSessionMatchesTransition(transition)
        case let .accountWork(lease):
            dependencies.session.isAccountWorkCurrent(lease)
        }
    }

    private func finishSourceOperation(_ operation: SourceOperation) {
        guard case let .accountWork(lease) = operation else { return }
        dependencies.session.finishAccountWork(lease)
    }
}
