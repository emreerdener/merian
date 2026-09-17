import Foundation

@MainActor
struct PurchaseIdentitySessionLiveOperations {
    let fetchLegacyProfile: @MainActor (
        UUID
    ) async throws -> LegacyPurchaseIdentityProfile?
    let linkLegacyProviderIdentity: @MainActor (
        PurchaseIdentityLegacyLinkRequest
    ) async -> Void
    let beginResolution: @MainActor () -> Void
    let resolve: @MainActor (
        String?,
        Bool
    ) async throws -> PurchasePrincipalBinding
    let applyStableBinding: @MainActor (
        PurchasePrincipalBinding,
        UUID,
        String
    ) async -> Void
    let currentProviderState: @MainActor () -> PurchaseIdentityProviderState
    let legacyProviderIsReady: @MainActor (UUID) -> Bool
    let entitlementIsReady: @MainActor (UUID) -> Bool
    let beginEntitlementSession: @MainActor (UUID) async -> Bool
    let reportLegacyProfileFailure: @MainActor (Error) -> Void
    let reportHandoffStateFailure: @MainActor (Error) -> Void
    let reportDeferredForHandoff: @MainActor () -> Void
    let reportResolutionFailure: @MainActor (Error) -> Void
}

/// Adapts Purchase Identity's provider-neutral session coordinators to the live
/// RevenueCat, entitlement, resolver, and legacy-profile effects. Auth state,
/// account-work admission, and durable handoff ownership remain injected by the
/// Auth composition root. This reference owner also preserves the facade's
/// fail-closed teardown boundary for deferred legacy linking and entitlement
/// refresh without owning either task.
@MainActor
final class PurchaseIdentitySessionLiveService {
    private let operations: PurchaseIdentitySessionLiveOperations

    init(operations: PurchaseIdentitySessionLiveOperations) {
        self.operations = operations
    }

    func snapshot(
        for profile: PurchaseIdentityLegacySessionProfile,
        isExpired: Bool = false
    ) -> PurchaseIdentitySessionSnapshot {
        PurchaseIdentitySessionSnapshot(
            userID: profile.userID,
            isAnonymous: profile.isAnonymous,
            isExpired: isExpired,
            linkLegacyProviderIdentity: { [weak self] in
                await self?.linkLegacyProviderIdentity(for: profile)
            }
        )
    }

    func linkLegacyProviderIdentity(
        for profile: PurchaseIdentityLegacySessionProfile
    ) async {
        let publicIdentity: LegacyPurchaseIdentityProfile?
        do {
            publicIdentity = try await operations.fetchLegacyProfile(
                profile.userID
            )
        } catch {
            publicIdentity = nil
            operations.reportLegacyProfileFailure(error)
        }

        await operations.linkLegacyProviderIdentity(
            PurchaseIdentityLegacyLinkRequest(
                userID: profile.userID,
                email: RevenueCatIdentityContext.firstNonEmpty(
                    profile.email,
                    publicIdentity?.email
                ),
                displayName: RevenueCatIdentityContext.firstNonEmpty(
                    profile.fullName,
                    profile.name,
                    publicIdentity?.publicAuthorName
                ),
                avatarURL: RevenueCatIdentityContext.firstNonEmpty(
                    profile.avatarURL,
                    profile.pictureURL,
                    publicIdentity?.publicAvatarURL
                ),
                publicUsername: publicIdentity?.publicUsername,
                publicAuthorName: publicIdentity?.publicAuthorName,
                publicIdentitySource: publicIdentity?.publicIdentitySource,
                accountKind: profile.accountKind
            )
        )
    }

    func legacyProviderIsReady(for userID: UUID) -> Bool {
        operations.legacyProviderIsReady(userID)
    }

    func dependencies(
        state: PurchaseIdentitySessionStateBoundary,
        handoff: PurchaseIdentitySessionHandoffBoundary
    ) -> PurchaseIdentitySessionDependencies {
        PurchaseIdentitySessionDependencies(
            state: state,
            provider: PurchaseIdentitySessionProviderBoundary(
                beginResolution: operations.beginResolution,
                resolve: operations.resolve,
                applyStableBinding: operations.applyStableBinding,
                currentState: operations.currentProviderState
            ),
            handoff: handoff,
            entitlement: PurchaseIdentityEntitlementBoundary(
                isReady: operations.entitlementIsReady,
                beginSession: { [weak self] userID in
                    guard let self else { return false }
                    return await operations.beginEntitlementSession(userID)
                }
            ),
            reportHandoffStateFailure:
                operations.reportHandoffStateFailure,
            reportDeferredForHandoff: operations.reportDeferredForHandoff,
            reportResolutionFailure: operations.reportResolutionFailure
        )
    }
}
