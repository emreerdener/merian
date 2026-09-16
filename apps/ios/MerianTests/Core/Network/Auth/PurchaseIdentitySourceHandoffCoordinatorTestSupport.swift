import Foundation
@testable import Merian

enum PurchaseIdentitySourceHandoffTestError: Error {
    case journal
    case operation
    case session
}

@MainActor
final class PurchaseIdentitySourceHandoffHarness {
    let sourceUserID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    let replacementUserID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )!
    let token = AuthTransitionToken(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .signOut
    )

    var events: [String] = []
    var currentSession: AuthTransitionSession?
    var currentPublishedUserID: UUID?
    var currentAuthGeneration: UInt64 = 7
    var ownsTransition = true
    var transitionMatches = true
    var accountWorkIsCurrent = true
    var allowsAccountWork = true
    var sessionError: Error?
    var legacyJournalError: Error?
    var stableJournalError: Error?
    var pendingLegacy: PendingSignOutPurchaseHandoff?
    var pendingStable: PendingPurchasePrincipalAuthRotation?
    var prepareStableError: Error?
    var prepareLegacyError: Error?
    var cancelStableError: Error?
    var cancelLegacyError: Error?
    var loadSDKSessionCallCount = 0
    var beforeSDKSessionReturn: (@MainActor (Int) async -> Void)?
    var mutateDuringStablePreparation: (() -> Void)?
    var mutateDuringLegacyPreparation: (() -> Void)?
    var mutateDuringStableCancellation: (() -> Void)?
    var mutateDuringLegacyCancellation: (() -> Void)?
    var adoptSourceResult = true
    var publishRestoredSourceResult = true
    private(set) var publishedPendingValues: [Bool] = []

    init() {
        currentSession = AuthTransitionSession(
            userID: sourceUserID,
            isAnonymous: false
        )
        currentPublishedUserID = sourceUserID
    }

    func dependencies() -> SourceHandoffDependencies {
        SourceHandoffDependencies(
            session: .init(
                currentAuthGeneration: {
                    self.currentAuthGeneration
                },
                currentPublishedUserID: {
                    self.currentPublishedUserID
                },
                currentSDKUserID: {
                    self.currentSession?.userID
                },
                ownsTransition: { _ in
                    self.ownsTransition
                },
                currentSessionMatchesTransition: { _ in
                    self.transitionMatches
                },
                beginUnownedAccountWork: { expectedUserID in
                    self.events.append("begin-account-work")
                    guard self.allowsAccountWork,
                          self.currentSession?.userID == expectedUserID else {
                        return nil
                    }
                    return AccountBoundWorkLease(
                        id: UUID(
                            uuidString:
                                "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
                        )!,
                        session: self.currentSession!
                    )
                },
                isAccountWorkCurrent: { _ in
                    self.accountWorkIsCurrent
                },
                finishAccountWork: { _ in
                    self.events.append("finish-account-work")
                },
                loadSDKSession: {
                    self.events.append("load-session")
                    self.loadSDKSessionCallCount += 1
                    await self.beforeSDKSessionReturn?(
                        self.loadSDKSessionCallCount
                    )
                    if let sessionError = self.sessionError {
                        throw sessionError
                    }
                    guard let currentSession = self.currentSession else {
                        throw PurchaseIdentitySourceHandoffTestError.session
                    }
                    return currentSession
                },
                adoptSourceSession: { sourceUserID, _ in
                    self.events.append("adopt-source")
                    return self.adoptSourceResult
                        && self.currentSession?.userID == sourceUserID
                },
                publishRestoredSource: { sourceUserID in
                    self.events.append("publish-source")
                    guard self.publishRestoredSourceResult else {
                        return false
                    }
                    self.currentPublishedUserID = sourceUserID
                    return true
                },
                restoredSourceIsCurrent: { sourceUserID, _ in
                    self.currentPublishedUserID == sourceUserID
                        && self.transitionMatches
                }
            ),
            journal: .init(
                loadLegacyHandoff: {
                    self.events.append("load-legacy")
                    if let legacyJournalError = self.legacyJournalError {
                        throw legacyJournalError
                    }
                    return self.pendingLegacy
                },
                loadStableRotation: {
                    self.events.append("load-stable")
                    if let stableJournalError = self.stableJournalError {
                        throw stableJournalError
                    }
                    return self.pendingStable
                },
                clearLegacyHandoff: {
                    self.events.append("clear-legacy")
                    self.pendingLegacy = nil
                },
                clearStableRotation: {
                    self.events.append("clear-stable")
                    self.pendingStable = nil
                },
                setHandoffPending: { pending in
                    self.events.append("pending-\(pending)")
                    self.publishedPendingValues.append(pending)
                }
            ),
            operations: .init(
                prepareStableRotation: { _, _ in
                    self.events.append("prepare-stable")
                    self.mutateDuringStablePreparation?()
                    if let prepareStableError = self.prepareStableError {
                        throw prepareStableError
                    }
                },
                prepareLegacyHandoff: { _ in
                    self.events.append("prepare-legacy")
                    self.mutateDuringLegacyPreparation?()
                    if let prepareLegacyError = self.prepareLegacyError {
                        throw prepareLegacyError
                    }
                },
                cancelStableRotation: { _ in
                    self.events.append("cancel-stable")
                    self.mutateDuringStableCancellation?()
                    if let cancelStableError = self.cancelStableError {
                        throw cancelStableError
                    }
                },
                cancelLegacyHandoff: { _ in
                    self.events.append("cancel-legacy")
                    self.mutateDuringLegacyCancellation?()
                    if let cancelLegacyError = self.cancelLegacyError {
                        throw cancelLegacyError
                    }
                },
                ensurePurchaseIdentityReady: { _, _ in
                    self.events.append("ensure-purchase-identity")
                },
                beginEntitlementSession: { _, _ in
                    self.events.append("begin-entitlement")
                }
            ),
            diagnostics: .init(
                reportPendingStateFailure: { _ in
                    self.events.append("diagnose-pending")
                },
                reportLegacyPreparation: {
                    self.events.append("diagnose-prepared-legacy")
                },
                reportLegacyAbandonment: {
                    self.events.append("diagnose-abandoned-legacy")
                },
                reportLegacyAbandonmentFailure: { _ in
                    self.events.append("diagnose-abandonment-failure")
                },
                reportSourceRestoration: {
                    self.events.append("diagnose-restored-source")
                }
            )
        )
    }

    func sourceContext() -> PurchaseIdentitySignOutSourceContext {
        PurchaseIdentitySignOutSourceContext(
            session: AuthTransitionSession(
                userID: sourceUserID,
                isAnonymous: false
            ),
            authGeneration: 7,
            binding: stableBinding(),
            purchaseProviderIsReady: true
        )
    }

    func installLegacyHandoff() {
        pendingLegacy = PendingSignOutPurchaseHandoff(
            sourceUserId: sourceUserID.uuidString.lowercased(),
            handoffId: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
            handoffSecret: "legacy-secret",
            expiresAt: "2026-09-15T12:10:00Z"
        )
    }

    func installStableRotation() {
        pendingStable = .server(
            ServerPrincipalRotation(
                protocolVersion: 3,
                localState: .prepared,
                rotationId: "ffffffff-ffff-ffff-ffff-ffffffffffff",
                rotationSecret: "rotation-secret",
                sourceUserId: sourceUserID.uuidString.lowercased(),
                purchasePrincipalId:
                    "11111111-1111-1111-1111-111111111111",
                revenueCatAppUserId: "merian_test_principal",
                bindingGeneration: 7,
                installationCapabilityFingerprint: String(
                    repeating: "f",
                    count: 64
                ),
                startedAt: "2026-09-15T12:00:00Z",
                expiresAt: "2026-09-15T12:10:00Z"
            )
        )
    }

    private func stableBinding() -> PurchasePrincipalBinding {
        try! PurchasePrincipalBinding(
            response: PurchasePrincipalResolveResponse(
                success: true,
                mode: "stable",
                purchase_principal_id:
                    "11111111-1111-1111-1111-111111111111",
                revenuecat_app_user_id: "merian_test_principal",
                binding_generation: 7,
                account_grants_allowed: true,
                minimum_client_protocol: PurchasePrincipalProtocol.current
            )
        )
    }
}
