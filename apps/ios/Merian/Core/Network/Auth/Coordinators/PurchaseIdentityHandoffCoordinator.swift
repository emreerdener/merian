import Foundation

/// Completes durable stable or compatibility purchase identity handoffs against
/// one exact anonymous Auth session and transition context. The coordinator
/// owns the keyed single-flight task; live SDK, provider, endpoint, journal,
/// entitlement, and logging effects arrive through narrow dependencies.
@MainActor
final class PurchaseIdentityHandoffCoordinator {
    private struct CompletionKey: Equatable {
        let targetUserID: String?
        let authGeneration: UInt64
        let transition: AuthTransitionToken?
    }

    private var task: Task<Bool, Never>?
    private var taskID: UUID?
    private var activeKey: CompletionKey?

    deinit {
        task?.cancel()
    }

    func completePendingHandoff(
        expectedDestinationUserID: String? = nil,
        expectedAuthGeneration: UInt64? = nil,
        ownedBy transition: AuthTransitionToken? = nil,
        dependencies: PurchaseIdentityHandoffDependencies
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let expectedUserID = expectedDestinationUserID?.lowercased()
            ?? dependencies.session.currentPublishedAnonymousUserID()
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard dependencies.session.currentSessionMatchesTransition(
                transition
            ) else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let lease = dependencies.session.beginUnownedAccountWork(
                expectedUserID.flatMap(UUID.init(uuidString:))
            ) else {
                return false
            }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                dependencies.session.finishAccountWork(accountWorkLease)
            }
        }

        let generation = expectedAuthGeneration
            ?? dependencies.session.currentAuthGeneration()
        let key = CompletionKey(
            targetUserID: expectedUserID,
            authGeneration: generation,
            transition: transition
        )
        if let task {
            if activeKey == key {
                return await task.value
            }
            cancel()
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performPendingHandoff(
                expectedDestinationUserID: expectedUserID,
                expectedAuthGeneration: generation,
                ownedBy: transition,
                dependencies: dependencies
            )
        }
        self.taskID = taskID
        activeKey = key
        self.task = task

        let result = await task.value
        if self.taskID == taskID {
            self.task = nil
            self.taskID = nil
            activeKey = nil
        }
        return result
    }

    func cancel() {
        task?.cancel()
        task = nil
        taskID = nil
        activeKey = nil
    }

    private func performPendingHandoff(
        expectedDestinationUserID: String?,
        expectedAuthGeneration: UInt64,
        ownedBy transition: AuthTransitionToken?,
        dependencies: PurchaseIdentityHandoffDependencies
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        do {
            if try dependencies.journal.loadLegacyHandoff() == nil,
               try dependencies.journal.loadStableRotation() != nil {
                return await completeStableRotation(
                    expectedDestinationUserID: expectedDestinationUserID,
                    expectedAuthGeneration: expectedAuthGeneration,
                    ownedBy: transition,
                    dependencies: dependencies
                )
            }
        } catch {
            guard !Task.isCancelled else { return false }
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportJournalSelectionFailure(error)
            return false
        }
        return await completeLegacyHandoff(
            expectedDestinationUserID: expectedDestinationUserID,
            expectedAuthGeneration: expectedAuthGeneration,
            ownedBy: transition,
            dependencies: dependencies
        )
    }

    private func completeStableRotation(
        expectedDestinationUserID: String?,
        expectedAuthGeneration: UInt64,
        ownedBy transition: AuthTransitionToken?,
        dependencies: PurchaseIdentityHandoffDependencies
    ) async -> Bool {
        let pending: ServerPrincipalRotation
        do {
            guard let loaded = try dependencies.journal
                .loadStableRotation() else {
                let legacyPending = try dependencies.journal
                    .loadLegacyHandoff() != nil
                dependencies.journal.setHandoffPending(legacyPending)
                return true
            }
            guard case let .server(serverRotation) = loaded,
                  serverRotation.localState == .prepared else {
                dependencies.journal.setHandoffPending(true)
                return false
            }
            pending = serverRotation
        } catch {
            guard !Task.isCancelled else { return false }
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportStableCompletionFailure(error)
            return false
        }

        dependencies.journal.setHandoffPending(true)
        do {
            try Task.checkCancellation()
            let session = try await dependencies.session.loadSDKSession()
            let destinationUserID = session.identity.userID.uuidString
                .lowercased()
            guard session.identity.isAnonymous,
                  destinationUserID != pending.sourceUserId.lowercased(),
                  expectedDestinationUserID.map({
                      $0.lowercased() == destinationUserID
                  }) ?? true,
                  dependencies.session.activeAnonymousSessionMatches(
                      destinationUserID,
                      expectedAuthGeneration,
                      transition
                  ) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            try Task.checkCancellation()
            guard let rotationID = UUID(uuidString: pending.rotationId) else {
                throw SupabaseAuthTransitionError
                    .purchasePrincipalRotationPersistenceFailed
            }
            let binding = try await dependencies.operations
                .claimStableRotation(
                    rotationID,
                    pending.rotationSecret,
                    pending.installationCapabilityFingerprint
                )
            try Task.checkCancellation()
            guard dependencies.session.activeAnonymousSessionMatches(
                    destinationUserID,
                    expectedAuthGeneration,
                    transition
                  ),
                  binding.mode == .stable,
                  binding.purchasePrincipalId?.uuidString.lowercased()
                    == pending.purchasePrincipalId.lowercased(),
                  binding.revenueCatAppUserId == pending.revenueCatAppUserId,
                  binding.bindingGeneration.map({
                      $0 > pending.bindingGeneration
                  }) == true else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }

            await dependencies.operations.applyStableBinding(
                binding,
                session.identity.userID
            )
            try Task.checkCancellation()
            guard dependencies.session.activeAnonymousSessionMatches(
                    destinationUserID,
                    expectedAuthGeneration,
                    transition
                  ),
                  dependencies.operations.stableProviderIdentityMatches(
                      session.identity.userID
                  ) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }

            guard await dependencies.operations.refreshEntitlement(
                session.identity.userID,
                transition
            ) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
            try await verifyActiveAnonymousSession(
                userID: destinationUserID,
                expectedAuthGeneration: expectedAuthGeneration,
                ownedBy: transition,
                dependencies: dependencies
            )
            try Task.checkCancellation()
            try dependencies.journal.clearStableRotation()
            let legacyPending = try dependencies.journal.loadLegacyHandoff()
                != nil
            dependencies.journal.setHandoffPending(legacyPending)
            dependencies.operations.recordLinkedUser(
                session.identity.userID
            )
            if !legacyPending {
                await dependencies.operations.refreshCustomerInfo()
            }
            dependencies.diagnostics.reportStableCompletion()
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportStableCompletionFailure(error)
            return false
        }
    }

    private func completeLegacyHandoff(
        expectedDestinationUserID: String?,
        expectedAuthGeneration: UInt64,
        ownedBy transition: AuthTransitionToken?,
        dependencies: PurchaseIdentityHandoffDependencies
    ) async -> Bool {
        guard !Task.isCancelled,
              !dependencies.session.isLocalSignOutInProgress() else {
            return false
        }

        let pending: PendingSignOutPurchaseHandoff
        do {
            guard let loaded = try dependencies.journal
                .loadLegacyHandoff() else {
                let stablePending = try dependencies.journal
                    .loadStableRotation() != nil
                dependencies.journal.setHandoffPending(stablePending)
                return true
            }
            pending = loaded
        } catch {
            guard !Task.isCancelled else { return false }
            dependencies.journal.setHandoffPending(true)
            dependencies.diagnostics.reportLegacyJournalFailure(error)
            return false
        }
        dependencies.journal.setHandoffPending(true)

        do {
            let session = try await dependencies.session.loadSDKSession()
            try Task.checkCancellation()
            let destinationUserID = session.identity.userID.uuidString
                .lowercased()
            guard session.identity.isAnonymous else {
                if destinationUserID == pending.sourceUserId.lowercased() {
                    await dependencies.operations
                        .abandonLegacyHandoffIfSourceRestored(
                            pending.sourceUserId,
                            transition
                        )
                }
                return false
            }
            if let expectedDestinationUserID,
               destinationUserID != expectedDestinationUserID {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            guard dependencies.session.activeAnonymousSessionMatches(
                destinationUserID,
                expectedAuthGeneration,
                transition
            ) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            try await PurchaseIdentitySignOutWorkflow
                .finalizeSignOutPurchaseHandoff(
                    bindDestination: {
                        try await dependencies.operations.bindLegacyHandoff(
                            pending,
                            destinationUserID
                        )
                    },
                    verifyBoundDestinationSession: {
                        try await self.verifyActiveAnonymousSession(
                            userID: destinationUserID,
                            expectedAuthGeneration: expectedAuthGeneration,
                            ownedBy: transition,
                            dependencies: dependencies
                        )
                    },
                    linkProviderIdentity: {
                        try await session.linkLegacyProviderIdentity()
                    },
                    verifyLinkedDestinationSession: {
                        try await self.verifyActiveAnonymousSession(
                            userID: destinationUserID,
                            expectedAuthGeneration: expectedAuthGeneration,
                            ownedBy: transition,
                            dependencies: dependencies
                        )
                    },
                    synchronizeStorePurchases: {
                        try await dependencies.operations
                            .synchronizeLegacyPurchases(
                                session.identity.userID
                            )
                    },
                    completeServerHandoff: {
                        try await dependencies.operations
                            .completeLegacyHandoff(pending)
                    },
                    refreshServerEntitlement: {
                        await dependencies.operations.refreshEntitlement(
                            session.identity.userID,
                            transition
                        )
                    },
                    verifyFinalDestinationSession: {
                        try await self.verifyActiveAnonymousSession(
                            userID: destinationUserID,
                            expectedAuthGeneration: expectedAuthGeneration,
                            ownedBy: transition,
                            dependencies: dependencies
                        )
                    },
                    clearPendingHandoff: {
                        try dependencies.journal.clearLegacyHandoff()
                    }
                )
            let stablePending = try dependencies.journal.loadStableRotation()
                != nil
            dependencies.journal.setHandoffPending(stablePending)
            await session.ensureTelemetryLinked(transition)
            dependencies.diagnostics.reportLegacyCompletion()
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            if dependencies.operations.shouldDiscardLegacyHandoff(error) {
                do {
                    try dependencies.journal.clearLegacyHandoff()
                    let stablePending = try dependencies.journal
                        .loadStableRotation() != nil
                    dependencies.journal.setHandoffPending(stablePending)
                } catch {
                    dependencies.journal.setHandoffPending(true)
                }
            }
            dependencies.diagnostics.reportLegacyCompletionFailure(error)
            return false
        }
    }

    private func verifyActiveAnonymousSession(
        userID: String,
        expectedAuthGeneration: UInt64,
        ownedBy transition: AuthTransitionToken?,
        dependencies: PurchaseIdentityHandoffDependencies
    ) async throws {
        try Task.checkCancellation()
        let session = try await dependencies.session.loadSDKSession()
        guard session.identity.isAnonymous,
              session.identity.userID.uuidString.caseInsensitiveCompare(
                  userID
              ) == .orderedSame,
              dependencies.session.activeAnonymousSessionMatches(
                  userID,
                  expectedAuthGeneration,
                  transition
              ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
    }
}
