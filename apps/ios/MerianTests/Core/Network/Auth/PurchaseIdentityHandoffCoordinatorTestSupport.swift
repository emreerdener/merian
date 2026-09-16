import Foundation
@testable import Merian

enum PurchaseHandoffTestError: Error, Equatable {
    case journal
    case operation
    case session
    case terminal
}

actor PurchaseHandoffTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilWaiterCount(_ expectedCount: Int) async {
        while !released && continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class PurchaseHandoffCoordinatorHarness {
    let sourceIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        isAnonymous: false
    )
    let anonymousIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        isAnonymous: true
    )
    let replacementIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        isAnonymous: true
    )
    let token = AuthTransitionToken(
        id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
        kind: .recovery
    )

    var events: [String] = []
    var currentIdentity: AuthTransitionSession?
    var currentAuthGeneration: UInt64 = 7
    var activeTransitionID: UUID?
    var transitionMatches = true
    var localSignOutIsInProgress = false
    var activeSessionMatches = true
    var legacyJournalError: Error?
    var stableJournalError: Error?
    var pendingLegacyHandoff: PendingSignOutPurchaseHandoff?
    var pendingStableRotation: PendingPurchasePrincipalAuthRotation?
    var stableClaimError: Error?
    var stableClaimGate: PurchaseHandoffTestGate?
    var legacyBindError: Error?
    var legacyBindGate: PurchaseHandoffTestGate?
    var legacyCompletionError: Error?
    var entitlementSucceeds = true
    var providerIdentityMatches = true
    var terminalErrors: [PurchaseHandoffTestError] = [.terminal]
    private(set) var handoffPending = false
    private(set) var stableClaimCount = 0
    private(set) var legacyBindCount = 0
    private(set) var stableClearCount = 0
    private(set) var legacyClearCount = 0

    func makeDependencies() -> PurchaseIdentityHandoffDependencies {
        PurchaseIdentityHandoffDependencies(
            session: .init(
                currentPublishedAnonymousUserID: {
                    guard self.currentIdentity?.isAnonymous == true else {
                        return nil
                    }
                    return self.currentIdentity?.userID.uuidString.lowercased()
                },
                currentAuthGeneration: {
                    self.currentAuthGeneration
                },
                isLocalSignOutInProgress: {
                    self.localSignOutIsInProgress
                },
                currentSessionMatchesTransition: { transition in
                    self.transitionMatches
                        && (self.activeTransitionID.map {
                            $0 == transition.id
                        } ?? true)
                },
                beginUnownedAccountWork: { expectedUserID in
                    self.events.append("begin-lease")
                    guard let identity = self.currentIdentity,
                          expectedUserID.map({ $0 == identity.userID })
                            ?? true else {
                        return nil
                    }
                    return AccountBoundWorkLease(
                        id: UUID(),
                        session: identity
                    )
                },
                finishAccountWork: { _ in
                    self.events.append("finish-lease")
                },
                loadSDKSession: {
                    self.events.append("load-session")
                    guard let identity = self.currentIdentity else {
                        throw PurchaseHandoffTestError.session
                    }
                    return self.snapshot(for: identity)
                },
                activeAnonymousSessionMatches: { userID, generation, transition in
                    let transitionMatches = if let transition {
                        self.activeTransitionID.map {
                            $0 == transition.id
                        } ?? self.transitionMatches
                    } else {
                        self.activeTransitionID == nil
                    }
                    return !Task.isCancelled
                        && self.activeSessionMatches
                        && transitionMatches
                        && self.currentIdentity?.isAnonymous == true
                        && self.currentIdentity?.userID.uuidString
                            .caseInsensitiveCompare(userID) == .orderedSame
                        && self.currentAuthGeneration == generation
                }
            ),
            journal: .init(
                loadLegacyHandoff: {
                    self.events.append("load-legacy")
                    if let legacyJournalError = self.legacyJournalError {
                        throw legacyJournalError
                    }
                    return self.pendingLegacyHandoff
                },
                loadStableRotation: {
                    self.events.append("load-stable")
                    if let stableJournalError = self.stableJournalError {
                        throw stableJournalError
                    }
                    return self.pendingStableRotation
                },
                clearLegacyHandoff: {
                    self.events.append("clear-legacy")
                    self.legacyClearCount += 1
                    self.pendingLegacyHandoff = nil
                },
                clearStableRotation: {
                    self.events.append("clear-stable")
                    self.stableClearCount += 1
                    self.pendingStableRotation = nil
                },
                setHandoffPending: { pending in
                    self.events.append("pending-\(pending)")
                    self.handoffPending = pending
                }
            ),
            operations: .init(
                claimStableRotation: { _, _, _ in
                    self.events.append("claim-stable")
                    self.stableClaimCount += 1
                    let stableClaimGate = self.stableClaimGate
                    self.stableClaimGate = nil
                    if let stableClaimGate {
                        await stableClaimGate.wait()
                    }
                    if let stableClaimError = self.stableClaimError {
                        throw stableClaimError
                    }
                    return self.stableBinding()
                },
                applyStableBinding: { _, userID in
                    self.events.append(
                        "apply-stable-\(userID.uuidString.lowercased())"
                    )
                },
                stableProviderIdentityMatches: { _ in
                    self.events.append("verify-provider")
                    return self.providerIdentityMatches
                },
                bindLegacyHandoff: { _, destinationUserID in
                    self.events.append("bind-legacy-\(destinationUserID)")
                    self.legacyBindCount += 1
                    let legacyBindGate = self.legacyBindGate
                    self.legacyBindGate = nil
                    let legacyBindError = self.legacyBindError
                    self.legacyBindError = nil
                    if let legacyBindGate {
                        await legacyBindGate.wait()
                    }
                    if let legacyBindError {
                        throw legacyBindError
                    }
                },
                synchronizeLegacyPurchases: { _ in
                    self.events.append("synchronize-legacy")
                },
                completeLegacyHandoff: { _ in
                    self.events.append("complete-legacy")
                    if let legacyCompletionError = self.legacyCompletionError {
                        throw legacyCompletionError
                    }
                },
                refreshEntitlement: { _, _ in
                    self.events.append("refresh-entitlement")
                    return self.entitlementSucceeds
                },
                refreshCustomerInfo: {
                    self.events.append("refresh-customer")
                },
                recordLinkedUser: { userID in
                    self.events.append(
                        "record-user-\(userID.uuidString.lowercased())"
                    )
                },
                abandonLegacyHandoffIfSourceRestored: { _, _ in
                    self.events.append("abandon-legacy")
                    self.pendingLegacyHandoff = nil
                },
                shouldDiscardLegacyHandoff: { error in
                    guard let error = error as? PurchaseHandoffTestError else {
                        return false
                    }
                    return self.terminalErrors.contains(error)
                }
            ),
            diagnostics: .init(
                reportJournalSelectionFailure: { _ in
                    self.events.append("diagnose-selection")
                },
                reportStableCompletionFailure: { _ in
                    self.events.append("diagnose-stable")
                },
                reportLegacyJournalFailure: { _ in
                    self.events.append("diagnose-legacy-journal")
                },
                reportLegacyCompletionFailure: { _ in
                    self.events.append("diagnose-legacy")
                },
                reportStableCompletion: {
                    self.events.append("stable-complete")
                },
                reportLegacyCompletion: {
                    self.events.append("legacy-complete")
                }
            )
        )
    }

    func installLegacyHandoff() {
        pendingLegacyHandoff = PendingSignOutPurchaseHandoff(
            sourceUserId: sourceIdentity.userID.uuidString.lowercased(),
            handoffId: "11111111-1111-1111-1111-111111111111",
            handoffSecret: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            expiresAt: "2026-09-14T00:10:00Z"
        )
    }

    func installStableRotation() {
        pendingStableRotation = .server(
            ServerPrincipalRotation(
                protocolVersion: 3,
                localState: .prepared,
                rotationId: "22222222-2222-2222-2222-222222222222",
                rotationSecret: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
                sourceUserId: sourceIdentity.userID.uuidString.lowercased(),
                purchasePrincipalId:
                    "33333333-3333-3333-3333-333333333333",
                revenueCatAppUserId: "MERIAN_PP_TEST",
                bindingGeneration: 7,
                installationCapabilityFingerprint: String(
                    repeating: "c",
                    count: 64
                ),
                startedAt: "2026-09-14T00:00:00Z",
                expiresAt: "2026-09-14T00:10:00Z"
            )
        )
    }

    private func snapshot(
        for identity: AuthTransitionSession
    ) -> PurchaseIdentityHandoffSessionSnapshot {
        PurchaseIdentityHandoffSessionSnapshot(
            identity: identity,
            linkLegacyProviderIdentity: {
                self.events.append("link-legacy-provider")
            },
            ensureTelemetryLinked: { _ in
                self.events.append("link-telemetry")
            }
        )
    }

    private func stableBinding() -> PurchasePrincipalBinding {
        try! PurchasePrincipalBinding(
            signOutRotationClaim: PrincipalRotationClaimResponse(
                success: true,
                operation: "claim_signout_rotation",
                rotation_id: "22222222-2222-2222-2222-222222222222",
                rotation_status: "completed",
                expires_at: "2026-09-14T00:10:00Z",
                purchase_principal_id:
                    "33333333-3333-3333-3333-333333333333",
                revenuecat_app_user_id: "MERIAN_PP_TEST",
                binding_generation: 8,
                account_grants_allowed: false,
                already_claimed: false
            )
        )
    }
}
