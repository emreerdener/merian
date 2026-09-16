import Foundation
@testable import Merian

@MainActor
final class AuthSessionLifecycleCoordinatorHarness {
    let session: AuthTransitionSession
    var events: [String] = []
    var diagnostics: [AuthSessionLifecycleDiagnostic] = []
    var accountDeletionCleanupPending = false
    var hasActiveTransition = false
    var isSigningOut = false
    var isUserSignOutTransitionInProgress = false
    var isTestExecution = false
    var currentPublishedSession = true
    var currentAuthGeneration: UInt64 = 7
    var publishedSession: AuthTransitionSession?
    var pendingGhostProfileMerge = false
    var pendingPurchaseIdentityHandoff = false
    var ghostProfileMergeReadError: Error?
    var purchaseHandoffReadError: Error?
    var ghostProfileMergeReadCount = 0
    var purchaseHandoffReadCount = 0
    var analyticsSuppressionValues: [Bool] = []
    var purchaseHandoffFenceValues: [Bool] = []
    var telemetryResults: [Bool] = [false]
    var suspendTelemetry: (@MainActor () async -> Void)?
    var clearHandoffOnCompletion = false
    var clearHandoffOnAbandonment = false
    var advanceGenerationAfterTelemetry = false
    var openTransitionAfterTelemetry = false
    var advanceGenerationAfterEntitlement = false
    var advanceGenerationAfterSignOut = false
    var openTransitionAfterSignOut = false

    init(
        userID: UUID = UUID(),
        isAnonymous: Bool = false
    ) {
        session = AuthTransitionSession(
            userID: userID,
            isAnonymous: isAnonymous
        )
        publishedSession = session
    }

    func dependencies() -> AuthSessionLifecycleDependencies {
        AuthSessionLifecycleDependencies(
            state: AuthSessionLifecycleStateBoundary(
                accountDeletionCleanupPending: {
                    self.accountDeletionCleanupPending
                },
                hasActiveTransition: {
                    self.hasActiveTransition
                },
                isSigningOut: {
                    self.isSigningOut
                },
                isUserSignOutTransitionInProgress: {
                    self.isUserSignOutTransitionInProgress
                },
                publishedSession: {
                    self.publishedSession
                },
                publishSDKSession: { session in
                    self.events.append("publish-authenticated")
                    guard session == self.session else { return false }
                    self.publishedSession = session
                    self.currentPublishedSession = true
                    return true
                },
                clearPublishedSession: {
                    self.events.append("clear-published-session")
                    self.publishedSession = nil
                    self.currentPublishedSession = false
                },
                clearPurchasePrincipalBinding: {
                    self.events.append("clear-purchase-binding")
                },
                clearLinkedUser: {
                    self.events.append("clear-linked-user")
                },
                beginPurchaseIdentityResolution: {
                    self.events.append("begin-purchase-resolution")
                },
                beginAccountSession: { _, _ in
                    self.events.append("begin-account-session")
                },
                observeConsentSession: { _ in
                    self.events.append("observe-consent-session")
                },
                schedulePublicAuthorIdentityRefresh: { _ in
                    self.events.append("schedule-author-refresh")
                },
                clearPublicAuthorIdentityRefreshMarker: {
                    self.events.append("clear-author-marker")
                },
                cancelPublicAuthorIdentityRefresh: {
                    self.events.append("cancel-author-refresh")
                },
                cancelAppleCredentialRevocation: {
                    self.events.append("cancel-apple-revocation")
                },
                cancelGhostProfileMerge: {
                    self.events.append("cancel-ghost-merge")
                },
                isCurrentPublishedSession: { session, generation in
                    self.events.append("validate-current-session")
                    return self.currentPublishedSession
                        && generation == self.currentAuthGeneration
                        && !self.hasActiveTransition
                        && session == self.session
                },
                isCurrentLifecycleSession: { session, generation in
                    self.events.append("validate-current-lifecycle")
                    return generation == self.currentAuthGeneration
                        && !self.hasActiveTransition
                        && self.publishedSession == session
                        && self.currentPublishedSession == (session != nil)
                }
            ),
            durability: AuthSessionLifecycleDurabilityBoundary(
                hasPendingGhostProfileMerge: {
                    self.ghostProfileMergeReadCount += 1
                    if let error = self.ghostProfileMergeReadError {
                        throw error
                    }
                    return self.pendingGhostProfileMerge
                },
                setAnalyticsSuppressedForGhostHandoff: { isSuppressed in
                    self.analyticsSuppressionValues.append(isSuppressed)
                },
                hasPendingPurchaseIdentityHandoff: {
                    self.purchaseHandoffReadCount += 1
                    if let error = self.purchaseHandoffReadError {
                        throw error
                    }
                    return self.pendingPurchaseIdentityHandoff
                },
                setPurchaseIdentityHandoffPending: { isPending in
                    self.purchaseHandoffFenceValues.append(isPending)
                }
            ),
            identity: AuthSessionLifecycleIdentityBoundary(
                isTestExecution: {
                    self.isTestExecution
                },
                isPurchaseIdentityHandoffPending: {
                    self.pendingPurchaseIdentityHandoff
                },
                completePendingPurchaseIdentityHandoff: { _, _ in
                    self.events.append("complete-purchase-handoff")
                    if self.clearHandoffOnCompletion {
                        self.pendingPurchaseIdentityHandoff = false
                    }
                },
                ensureTelemetryLinked: { _ in
                    self.events.append("ensure-telemetry")
                    if let suspendTelemetry = self.suspendTelemetry {
                        await suspendTelemetry()
                    }
                    if self.advanceGenerationAfterTelemetry {
                        self.currentAuthGeneration &+= 1
                    }
                    if self.openTransitionAfterTelemetry {
                        self.hasActiveTransition = true
                    }
                    guard !self.telemetryResults.isEmpty else { return false }
                    return self.telemetryResults.removeFirst()
                },
                abandonRestoredSourceHandoffs: { _ in
                    self.events.append("abandon-source-handoffs")
                    if self.clearHandoffOnAbandonment {
                        self.pendingPurchaseIdentityHandoff = false
                    }
                },
                clearEntitlementSession: {
                    self.events.append("clear-entitlement")
                },
                beginEntitlementSession: { _ in
                    self.events.append("begin-entitlement")
                    if self.advanceGenerationAfterEntitlement {
                        self.currentAuthGeneration &+= 1
                    }
                },
                handleSupabaseSignOut: {
                    self.events.append("purchase-sign-out")
                    if self.advanceGenerationAfterSignOut {
                        self.currentAuthGeneration &+= 1
                    }
                    if self.openTransitionAfterSignOut {
                        self.hasActiveTransition = true
                    }
                },
                scheduleHistoricalSync: { _, _ in
                    self.events.append("schedule-historical-sync")
                }
            ),
            diagnose: { diagnostic, _ in
                self.diagnostics.append(diagnostic)
            }
        )
    }

    func event(
        adoption: AuthSessionAdoption? = nil,
        authGeneration: UInt64 = 7,
        origin: AuthSessionLifecycleOrigin = .initialRestoration
    ) -> AuthSessionLifecycleEvent {
        AuthSessionLifecycleEvent(
            adoption: adoption ?? .authenticated(userId: session.userID),
            session: adoption == .signedOut ? nil : session,
            authGeneration: authGeneration,
            origin: origin
        )
    }
}

enum AuthSessionLifecycleCoordinatorTestError: Error {
    case unreadable
}
