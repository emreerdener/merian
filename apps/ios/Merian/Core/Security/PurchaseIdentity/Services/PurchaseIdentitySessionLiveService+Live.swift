import os
import Supabase

extension PurchaseIdentitySessionLiveService {
    static func live(
        client: SupabaseClient,
        resolver: PurchasePrincipalResolver,
        legacyProfileService: LegacyPurchaseIdentityProfileService
    ) -> Self {
        Self(
            operations: PurchaseIdentitySessionLiveOperations(
                fetchLegacyProfile: { userID in
                    try await legacyProfileService.fetch(for: userID)
                },
                linkLegacyProviderIdentity: { request in
                    await RevenueCatManager.shared.linkWithSupabase(
                        userId: request.userID,
                        email: request.email,
                        displayName: request.displayName,
                        avatarUrl: request.avatarURL,
                        publicUsername: request.publicUsername,
                        publicAuthorName: request.publicAuthorName,
                        publicIdentitySource: request.publicIdentitySource,
                        accountKind: request.accountKind
                    )
                },
                beginResolution: {
                    RevenueCatManager.shared
                        .beginPurchaseIdentityResolution()
                },
                resolve: { fingerprint, allowsCreation in
                    try await resolver.resolve(
                        expectedCapabilityFingerprint: fingerprint,
                        allowsCapabilityCreation: allowsCreation
                    )
                },
                applyStableBinding: { binding, userID, accountKind in
                    await RevenueCatManager.shared
                        .linkResolvedPurchasePrincipal(
                            binding,
                            authUserID: userID,
                            accountKind: accountKind
                        )
                },
                currentProviderState: {
                    PurchaseIdentityProviderState(
                        isIdentityReady:
                            RevenueCatManager.shared.isIdentityReady,
                        linkedAuthUserID:
                            RevenueCatManager.shared.linkedAuthUserID,
                        linkedAccountKind:
                            RevenueCatManager.shared.linkedAccountKind
                    )
                },
                legacyProviderIsReady: { userID in
                    let manager = RevenueCatManager.shared
                    return manager.isIdentityReady
                        && !manager.usesStablePurchasePrincipal
                        && manager.linkedAppUserID
                            == RevenueCatAppUserIDPolicy.canonicalID(
                                for: userID
                            )
                        && manager.linkedAuthUserID == userID
                },
                entitlementIsReady: { userID in
                    EntitlementManager.shared.activeAccountID == userID
                        && EntitlementManager.shared
                            .isVerifiedForCurrentLaunch
                },
                beginEntitlementSession: { userID in
                    await EntitlementManager.shared.beginSession(
                        userID: userID,
                        client: client
                    )
                },
                reportLegacyProfileFailure: { error in
                    MerianLog.auth.debug(
                        "RevenueCat public identity lookup failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                },
                reportHandoffStateFailure: { _ in
                    MerianLog.auth.error(
                        "Deferred external identity linking because sign-out purchase state is unreadable."
                    )
                },
                reportDeferredForHandoff: {
                    MerianLog.auth.debug(
                        "Deferred external identity linking until the sign-out purchase destination is bound."
                    )
                },
                reportResolutionFailure: { error in
                    MerianLog.auth.debug(
                        "Purchase identity resolution failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                }
            )
        )
    }
}
