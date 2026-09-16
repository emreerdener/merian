import Foundation
@testable import Merian

@MainActor
final class PurchaseIdentitySessionCoordinatorHarness {
    struct SDKState {
        let userID: UUID
        let isAnonymous: Bool
        let isExpired: Bool
    }

    let userID: UUID
    var authGeneration: UInt64 = 7
    var publishedUserID: UUID?
    var publishedIsAnonymous = false
    var isTestExecution = false
    var accountDeletionCleanupPending = false
    var isSigningOut = false
    var isAuthenticated = true
    var isUserSignOutTransitionInProgress = false
    var admitsAccountWork = true
    var accountWorkIsCurrent = true
    var accountWorkFinishCount = 0
    var sdkStates: [SDKState] = []
    var sdkLoadCount = 0

    var handoffPending = false
    var handoffReadError: Error?
    var handoffReadCount = 0
    var publishedHandoffValues: [Bool] = []
    var completeHandoffResult = true
    var clearsHandoffOnAbandonment = false

    var binding: PurchasePrincipalBinding = .legacyFallback
    var resolutionError: Error?
    var resolutionCount = 0
    var suspendResolution = false
    var advanceGenerationDuringResolution = false
    var providerState = PurchaseIdentityProviderState(
        isIdentityReady: false,
        linkedAuthUserID: nil,
        linkedAccountKind: nil
    )
    var providerBecomesReadyAfterLink = true
    var resolutionContinuations:
        [CheckedContinuation<PurchasePrincipalBinding, Error>] = []

    var entitlementReady = false
    var entitlementResult = true
    var advanceGenerationDuringEntitlement = false
    var events: [String] = []
    var resolutionFailures = 0
    var handoffFailures = 0

    init(
        userID: UUID = UUID(),
        isAnonymous: Bool = false
    ) {
        self.userID = userID
        publishedUserID = userID
        publishedIsAnonymous = isAnonymous
        sdkStates = [
            SDKState(
                userID: userID,
                isAnonymous: isAnonymous,
                isExpired: false
            )
        ]
    }

    var context: PurchaseIdentitySessionContext {
        PurchaseIdentitySessionContext(
            userID: userID,
            isAnonymous: publishedIsAnonymous,
            authGeneration: authGeneration
        )
    }

    func snapshot(
        userID: UUID? = nil,
        isAnonymous: Bool? = nil,
        isExpired: Bool = false
    ) -> PurchaseIdentitySessionSnapshot {
        let snapshotUserID = userID ?? self.userID
        let snapshotIsAnonymous = isAnonymous ?? publishedIsAnonymous
        return PurchaseIdentitySessionSnapshot(
            userID: snapshotUserID,
            isAnonymous: snapshotIsAnonymous,
            isExpired: isExpired,
            linkLegacyProviderIdentity: {
                self.events.append("link-legacy")
                self.publishProviderReady(
                    userID: snapshotUserID,
                    isAnonymous: snapshotIsAnonymous
                )
            }
        )
    }

    func dependencies() -> PurchaseIdentitySessionDependencies {
        PurchaseIdentitySessionDependencies(
            state: PurchaseIdentitySessionStateBoundary(
                isTestExecution: { self.isTestExecution },
                accountDeletionCleanupPending: {
                    self.accountDeletionCleanupPending
                },
                isSigningOut: { self.isSigningOut },
                isAuthenticated: { self.isAuthenticated },
                isUserSignOutTransitionInProgress: {
                    self.isUserSignOutTransitionInProgress
                },
                currentPublishedSession: {
                    guard let publishedUserID = self.publishedUserID else {
                        return nil
                    }
                    return PurchaseIdentitySessionContext(
                        userID: publishedUserID,
                        isAnonymous: self.publishedIsAnonymous,
                        authGeneration: self.authGeneration
                    )
                },
                isCurrentPublishedSession: { context in
                    self.publishedUserID == context.userID
                        && self.publishedIsAnonymous == context.isAnonymous
                        && self.authGeneration == context.authGeneration
                },
                beginAccountWork: { _ in
                    guard self.admitsAccountWork else { return nil }
                    return PurchaseIdentityAccountWorkLease(
                        isCurrent: { self.accountWorkIsCurrent },
                        finish: { self.accountWorkFinishCount += 1 }
                    )
                },
                loadSDKSession: {
                    self.sdkLoadCount += 1
                    let index = min(
                        self.sdkLoadCount - 1,
                        self.sdkStates.count - 1
                    )
                    let state = self.sdkStates[index]
                    return self.snapshot(
                        userID: state.userID,
                        isAnonymous: state.isAnonymous,
                        isExpired: state.isExpired
                    )
                }
            ),
            provider: PurchaseIdentitySessionProviderBoundary(
                beginResolution: {
                    self.events.append("begin-resolution")
                    self.providerState = PurchaseIdentityProviderState(
                        isIdentityReady: false,
                        linkedAuthUserID: nil,
                        linkedAccountKind: nil
                    )
                },
                resolve: { _, _ in
                    self.events.append("resolve")
                    self.resolutionCount += 1
                    if self.suspendResolution {
                        return try await withCheckedThrowingContinuation {
                            self.resolutionContinuations.append($0)
                        }
                    }
                    if let resolutionError = self.resolutionError {
                        throw resolutionError
                    }
                    if self.advanceGenerationDuringResolution {
                        self.authGeneration &+= 1
                    }
                    return self.binding
                },
                applyStableBinding: { _, userID, accountKind in
                    self.events.append("link-stable")
                    guard self.providerBecomesReadyAfterLink else { return }
                    self.providerState = PurchaseIdentityProviderState(
                        isIdentityReady: true,
                        linkedAuthUserID: userID,
                        linkedAccountKind: accountKind
                    )
                },
                currentState: { self.providerState }
            ),
            handoff: PurchaseIdentitySessionHandoffBoundary(
                loadPending: {
                    self.handoffReadCount += 1
                    if let handoffReadError = self.handoffReadError {
                        throw handoffReadError
                    }
                    return self.handoffPending
                },
                setPending: {
                    self.publishedHandoffValues.append($0)
                },
                completePending: { _ in
                    self.events.append("complete-handoff")
                    return self.completeHandoffResult
                },
                abandonRestoredSource: { _ in
                    self.events.append("abandon-handoff")
                    if self.clearsHandoffOnAbandonment {
                        self.handoffPending = false
                    }
                }
            ),
            entitlement: PurchaseIdentityEntitlementBoundary(
                isReady: { _ in self.entitlementReady },
                beginSession: { _ in
                    self.events.append("begin-entitlement")
                    if self.advanceGenerationDuringEntitlement {
                        self.authGeneration &+= 1
                    }
                    return self.entitlementResult
                }
            ),
            reportHandoffStateFailure: { _ in
                self.handoffFailures += 1
            },
            reportDeferredForHandoff: {
                self.events.append("defer-handoff")
            },
            reportResolutionFailure: { _ in
                self.resolutionFailures += 1
            }
        )
    }

    func resumeResolution(
        at index: Int = 0,
        returning resolvedBinding: PurchasePrincipalBinding? = nil
    ) {
        guard resolutionContinuations.indices.contains(index) else { return }
        let continuation = resolutionContinuations.remove(at: index)
        if resolutionContinuations.isEmpty {
            suspendResolution = false
        }
        continuation.resume(returning: resolvedBinding ?? binding)
    }

    func resumeAllResolutions() {
        while !resolutionContinuations.isEmpty {
            resumeResolution()
        }
    }

    static func stableBinding() throws -> PurchasePrincipalBinding {
        try PurchasePrincipalBinding(
            response: PurchasePrincipalResolveResponse(
                success: true,
                mode: "stable",
                purchase_principal_id: UUID().uuidString,
                revenuecat_app_user_id: "merian_\(UUID().uuidString)",
                binding_generation: 4,
                account_grants_allowed: true,
                minimum_client_protocol: PurchasePrincipalProtocol.current
            )
        )
    }

    private func publishProviderReady(
        userID: UUID,
        isAnonymous: Bool
    ) {
        guard providerBecomesReadyAfterLink else { return }
        providerState = PurchaseIdentityProviderState(
            isIdentityReady: true,
            linkedAuthUserID: userID,
            linkedAccountKind: RevenueCatAccountMutationPolicy.accountKind(
                isAnonymous: isAnonymous
            )
        )
    }
}

enum PurchaseIdentitySessionCoordinatorTestError: Error {
    case failed
}
