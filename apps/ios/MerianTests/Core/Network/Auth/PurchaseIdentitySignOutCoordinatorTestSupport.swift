import Foundation
@testable import Merian

enum PurchaseSignOutTestError: Error {
    case journal
    case preparation
    case session
}

@MainActor
final class PurchaseSignOutCoordinatorHarness {
    let sourceIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        isAnonymous: false
    )
    let anonymousIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        isAnonymous: true
    )
    let unrelatedIdentity = AuthTransitionSession(
        userID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        isAnonymous: false
    )
    let token = AuthTransitionToken(
        id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
        kind: .signOut
    )

    var events: [String] = []
    var transitionCanBegin = true
    var transitionIsOwned = false
    var transitionMatches = true
    var quiescenceSucceeds = true
    var sdkIdentity: AuthTransitionSession?
    var fallbackIdentity: AuthTransitionSession?
    var sdkSessionError: Error?
    var hasKnownLinkedIdentity = false
    var initializedIdentity: AuthTransitionSession?
    var cancelDuringAnonymousInitialization = false
    var sourceContextIsAvailable = true
    var sourceMode: PurchasePrincipalResolutionMode = .stable
    var purchaseProviderIsReady = true
    var legacyJournalError: Error?
    var stableJournalError: Error?
    var stableJournalErrorOnRead: Int?
    private(set) var stableJournalReadCount = 0
    var pendingLegacyHandoff: PendingSignOutPurchaseHandoff?
    var pendingStableRotation: PendingPurchasePrincipalAuthRotation?
    var preparationError: Error?
    var completionSucceeds = true

    func makeCoordinator() -> PurchaseIdentitySignOutCoordinator {
        PurchaseIdentitySignOutCoordinator(dependencies: makeDependencies())
    }

    func makeDependencies()
        -> PurchaseSignOutDependencies {
        let session = PurchaseIdentitySignOutSessionBoundary(
            beginTransition: { kind in
                self.events.append("begin-\(Self.name(of: kind))")
                guard self.transitionCanBegin else { return nil }
                self.transitionIsOwned = true
                return AuthTransitionToken(id: self.token.id, kind: kind)
            },
            finishTransition: { _ in
                self.events.append("finish")
                self.transitionIsOwned = false
            },
            updateTransition: { _, phase in
                self.events.append("phase-\(phase.rawValue)")
            },
            ownsTransition: { _ in
                self.transitionIsOwned
            },
            awaitAccountBoundWorkQuiescence: {
                self.events.append("quiesce")
                return self.quiescenceSucceeds
            },
            loadSDKSession: {
                self.events.append("load-sdk-session")
                if let sdkSessionError = self.sdkSessionError {
                    throw sdkSessionError
                }
                guard let identity = self.sdkIdentity else {
                    throw PurchaseSignOutTestError.session
                }
                return self.snapshot(for: identity)
            },
            fallbackPublishedSession: {
                self.events.append("load-fallback-session")
                guard let identity = self.fallbackIdentity else {
                    return nil
                }
                return self.snapshot(for: identity)
            },
            hasKnownLinkedIdentity: {
                self.hasKnownLinkedIdentity
            },
            initializeAnonymousSession: { _ in
                self.events.append("initialize-anonymous")
                if self.cancelDuringAnonymousInitialization {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                return self.initializedIdentity
            },
            performLocalSignOut: { _ in
                self.events.append("sign-out")
            },
            resolveLinkedSourceContext: { starting, transition in
                self.events.append("resolve-source")
                await starting.ensureTelemetryLinked(transition)
                guard self.sourceContextIsAvailable,
                      let binding = self.binding() else {
                    return nil
                }
                return PurchaseIdentitySignOutSourceContext(
                    session: starting.identity,
                    authGeneration: 7,
                    binding: binding,
                    purchaseProviderIsReady:
                        self.purchaseProviderIsReady
                )
            },
            currentSessionMatchesTransition: { _ in
                self.transitionIsOwned && self.transitionMatches
            }
        )
        let journal = PurchaseIdentitySignOutJournalBoundary(
            loadLegacyHandoff: {
                self.events.append("load-legacy")
                if let legacyJournalError = self.legacyJournalError {
                    throw legacyJournalError
                }
                return self.pendingLegacyHandoff
            },
            loadStableRotation: {
                self.events.append("load-stable")
                self.stableJournalReadCount += 1
                if let errorRead = self.stableJournalErrorOnRead,
                   self.stableJournalReadCount == errorRead {
                    throw PurchaseSignOutTestError.journal
                }
                if let stableJournalError = self.stableJournalError {
                    throw stableJournalError
                }
                return self.pendingStableRotation
            },
            setHandoffPending: { isPending in
                self.events.append("pending-\(isPending)")
            },
            completePendingHandoff: { destination, _ in
                self.events.append(
                    "complete-\(destination?.lowercased() ?? "current")"
                )
                return self.completionSucceeds
            },
            abandonStableRotationIfSourceRestored: { _, _ in
                self.events.append("abandon-stable")
                self.pendingStableRotation = nil
            },
            abandonLegacyHandoffIfSourceRestored: { _, _ in
                self.events.append("abandon-legacy")
                self.pendingLegacyHandoff = nil
            },
            prepareStableRotation: { _, _ in
                self.events.append("prepare-stable")
                if let preparationError = self.preparationError {
                    throw preparationError
                }
            },
            prepareLegacyHandoff: { _, _ in
                self.events.append("prepare-legacy")
                if let preparationError = self.preparationError {
                    throw preparationError
                }
            },
            restoreSourceIdentityAfterFailedSignOut: { _, _ in
                self.events.append("restore-source")
            }
        )
        let diagnostics = PurchaseIdentitySignOutDiagnostics(
            reportUnreadableJournal: {
                self.events.append("diagnose-unreadable-journal")
            },
            reportUnverifiedLinkedSession: {
                self.events.append("diagnose-unverified-session")
            },
            reportUnrelatedStableRotation: {
                self.events.append("diagnose-unrelated-stable")
            },
            reportUnrelatedLegacyHandoff: {
                self.events.append("diagnose-unrelated-legacy")
            },
            reportTransitionFailure: { _ in
                self.events.append("diagnose-transition-failure")
            }
        )
        return PurchaseSignOutDependencies(
            session: session,
            journal: journal,
            diagnostics: diagnostics
        )
    }

    func installStableRotation(sourceUserID: UUID? = nil) {
        let sourceUserID = sourceUserID ?? sourceIdentity.userID
        pendingStableRotation = .legacy(
            LegacyPrincipalRotation(
                sourceUserId: sourceUserID.uuidString.lowercased(),
                purchasePrincipalId:
                    "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
                revenueCatAppUserId: "MERIAN_PP_TEST",
                installationCapabilityFingerprint:
                    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                startedAt: "2026-09-14T00:00:00Z"
            )
        )
    }

    func installLegacyHandoff(sourceUserID: UUID? = nil) {
        let sourceUserID = sourceUserID ?? sourceIdentity.userID
        pendingLegacyHandoff = PendingSignOutPurchaseHandoff(
            sourceUserId: sourceUserID.uuidString.lowercased(),
            handoffId: "11111111-1111-1111-1111-111111111111",
            handoffSecret:
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            expiresAt: "2026-09-14T00:10:00Z"
        )
    }

    private func snapshot(
        for identity: AuthTransitionSession
    ) -> PurchaseIdentitySignOutSessionSnapshot {
        PurchaseIdentitySignOutSessionSnapshot(
            identity: identity,
            ensureTelemetryLinked: { _ in
                self.events.append("link-telemetry")
            }
        )
    }

    private func binding() -> PurchasePrincipalBinding? {
        switch sourceMode {
        case .legacy:
            .legacyFallback
        case .stable:
            try? PurchasePrincipalBinding(
                response: PurchasePrincipalResolveResponse(
                    success: true,
                    mode: "stable",
                    purchase_principal_id:
                        "22222222-2222-2222-2222-222222222222",
                    revenuecat_app_user_id: "MERIAN_PP_TEST",
                    binding_generation: 7,
                    account_grants_allowed: false,
                    minimum_client_protocol: 3
                )
            )
        }
    }

    private static func name(of kind: AuthTransitionKind) -> String {
        switch kind {
        case .signOut:
            "sign-out"
        case .recovery:
            "recovery"
        default:
            "unexpected"
        }
    }
}
