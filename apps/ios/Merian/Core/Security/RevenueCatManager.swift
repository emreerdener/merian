import Observation
import os
@_spi(Internal) import RevenueCat
import UIKit

@MainActor
@Observable final class RevenueCatManager {
    static let shared = RevenueCatManager()
    private init() {}

    // MARK: - State

    var isProActive: Bool = false
    var isSubscribed: Bool = false

    /// Funding policy for a new scan. An active complimentary hold preserves
    /// functional Pro access but cannot be spent by another analysis.
    var canStartProScan: Bool {
        !isPurchaseIdentityHandoffPending
            && (isSubscribed || EntitlementManager.shared.canStartProFundedScan)
    }

    var currentOfferings: Offerings?
    var isFetchingOfferings: Bool = false

    @ObservationIgnored private let identityCoordinator =
        RevenueCatIdentityCoordinator()

    var linkedAppUserID: String? {
        identityCoordinator.linkedAppUserID
    }

    var linkedAuthUserID: UUID? {
        identityCoordinator.linkedAuthUserID
    }

    var linkedBindingGeneration: Int64? {
        identityCoordinator.linkedBindingGeneration
    }

    var usesStablePurchasePrincipal: Bool {
        identityCoordinator.usesStablePurchasePrincipal
    }

    var linkedAccountKind: String? {
        identityCoordinator.linkedAccountKind
    }

    /// A device-durable StoreKit identity transfer is unresolved. RevenueCat
    /// may already be linked to the destination, but user-initiated provider
    /// mutations remain disabled until the server verifies continuity.
    var isPurchaseIdentityHandoffPending: Bool {
        identityCoordinator.isPurchaseIdentityHandoffPending
    }

    /// RevenueCat and the active Supabase session agree on the exact canonical
    /// custom identity. This includes both Ghost and permanent accounts.
    var isIdentityReady: Bool {
        guard let linkedAppUserID else { return false }
        return isCurrentIdentity(linkedAppUserID)
    }

    /// Provider mutations are allowed only after RevenueCat is linked to the
    /// exact stable Supabase identity and account kind. Both Ghost and
    /// permanent accounts may purchase.
    var isPurchaseIdentityReady: Bool {
        guard let linkedAppUserID else { return false }
        return identityCoordinator.isPurchaseIdentityReady(
            providerIdentityReady: isCurrentIdentity(linkedAppUserID)
        )
    }

    func setPurchaseIdentityHandoffPending(_ pending: Bool) {
        identityCoordinator.setPurchaseIdentityHandoffPending(pending)
        if pending {
            closePaidReadiness()
        }
    }

    /// Closes provider mutation readiness before an asynchronous server mode
    /// decision. A resolver timeout, rollback response, or stale Auth result
    /// must not leave the previous RevenueCat customer usable merely because
    /// the SDK is still configured to it. The next successful exact binding
    /// reopens readiness without creating an anonymous provider customer.
    func beginPurchaseIdentityResolution() {
        identityCoordinator.beginPurchaseIdentityResolution()
        closePaidReadiness()
    }

    private func closePaidReadiness() {
        isSubscribed = false
        currentOfferings = nil
        isFetchingOfferings = false
        synchronizeFunctionalEntitlement()
    }

    private func isCurrentIdentity(_ appUserID: String) -> Bool {
        guard !TestExecutionCoordinator.isRunningTests,
              Purchases.isConfigured,
              identityCoordinator.hasCurrentLinkedIdentity(appUserID) else {
            return false
        }

        return !Purchases.shared.isAnonymous && Purchases.shared.appUserID == appUserID
    }

    private func isCurrentProviderMutationIdentity(_ appUserID: String) -> Bool {
        identityCoordinator.isProviderMutationIdentityReady(
            providerIdentityReady: isCurrentIdentity(appUserID)
        )
    }

    private func currentProviderOperationContext()
        -> RevenueCatProviderOperationContext? {
        guard let appUserID = linkedAppUserID,
              identityCoordinator.isPurchaseIdentityReady(
                  providerIdentityReady: isCurrentIdentity(appUserID)
              ) else { return nil }
        return identityCoordinator.providerOperationContext(
            appUserID: appUserID
        )
    }

    private func isCurrentProviderOperation(
        _ context: RevenueCatProviderOperationContext
    ) -> Bool {
        currentProviderOperationContext() == context
    }

    // MARK: - Configuration

    private func validatedAPIKey() -> String? {
        let apiKey = MerianEnvironment.revenueCatApiKey
        guard !apiKey.isEmpty else {
            MerianLog.general.error("RevenueCat configuration skipped because REVENUECAT_API_KEY is missing.")
            return nil
        }

        #if !DEBUG
        if apiKey.hasPrefix("test_") {
            MerianLog.general.error("RevenueCat configuration skipped because Release builds require an appl_ production iOS key, not a Test Store key.")
            return nil
        }
        #endif

        return apiKey
    }

    // MARK: - Identity

    /// Configures or switches RevenueCat directly to the canonical Supabase UUID.
    /// Merian intentionally never creates or logs out to a RevenueCat anonymous ID.
    func linkWithSupabase(
        userId: UUID,
        email: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        publicUsername: String? = nil,
        publicAuthorName: String? = nil,
        publicIdentitySource: String? = nil,
        accountKind: String? = nil
    ) async {
        let appUserID = RevenueCatAppUserIDPolicy.canonicalID(for: userId)
        let normalizedAccountKind = RevenueCatAccountMutationPolicy.normalizedAccountKind(accountKind)
        let identity = RevenueCatIdentityContext(
            userId: appUserID,
            email: email,
            displayName: displayName,
            avatarUrl: avatarUrl,
            publicUsername: publicUsername,
            publicAuthorName: publicAuthorName,
            publicIdentitySource: publicIdentitySource,
            accountKind: normalizedAccountKind
        )

        await linkIdentity(
            appUserID: appUserID,
            authUserID: userId,
            bindingGeneration: 0,
            accountKind: normalizedAccountKind,
            accountGrantsAllowed: true,
            stablePurchasePrincipal: false,
            legacyIdentityAttributes: identity
        )
    }

    /// Links the server-resolved stable purchase principal to one exact Auth
    /// session. No account PII or Auth UUID is written onto the shared
    /// RevenueCat customer; the private server binding owns that relationship.
    func linkResolvedPurchasePrincipal(
        _ binding: PurchasePrincipalBinding,
        authUserID: UUID,
        accountKind: String
    ) async {
        guard binding.mode == .stable,
              let appUserID = binding.revenueCatAppUserId,
              let generation = binding.bindingGeneration else {
            return
        }
        await linkIdentity(
            appUserID: appUserID,
            authUserID: authUserID,
            bindingGeneration: generation,
            accountKind: accountKind,
            accountGrantsAllowed: binding.accountGrantsAllowed,
            stablePurchasePrincipal: true,
            legacyIdentityAttributes: nil
        )
    }

    private func linkIdentity(
        appUserID: String,
        authUserID: UUID,
        bindingGeneration: Int64,
        accountKind: String?,
        accountGrantsAllowed: Bool,
        stablePurchasePrincipal: Bool,
        legacyIdentityAttributes: RevenueCatIdentityContext?
    ) async {
        guard !TestExecutionCoordinator.isRunningTests else { return }

        let normalizedAccountKind = RevenueCatAccountMutationPolicy
            .normalizedAccountKind(accountKind)
        let request = RevenueCatIdentityCoordinator.Request(
            appUserID: appUserID,
            authUserID: authUserID,
            bindingGeneration: bindingGeneration,
            accountKind: normalizedAccountKind,
            accountGrantsAllowed: accountGrantsAllowed,
            usesStablePurchasePrincipal: stablePurchasePrincipal
        )
        await identityCoordinator.link(
            request,
            resetPaidReadiness: { [weak self] in
                self?.closePaidReadiness()
            },
            operation: { [weak self] context in
                guard let self else { return }
                await self.performIdentityLink(
                    context: context,
                    legacyIdentityAttributes: legacyIdentityAttributes
                )
            }
        )
    }

    private func performIdentityLink(
        context: RevenueCatIdentityCoordinator.Context,
        legacyIdentityAttributes: RevenueCatIdentityContext?
    ) async {
        guard identityCoordinator.isCurrentRequest(context) else { return }
        let request = context.request
        let appUserID = request.appUserID

        Purchases.logLevel = .warn
        Purchases.logHandler = { level, _ in
            guard let message = RevenueCatSDKLogPrivacyPolicy.safeMessage(
                for: level
            ) else { return }
            if level == .error {
                MerianLog.general.error("\(message, privacy: .public)")
            } else {
                MerianLog.general.warning("\(message, privacy: .public)")
            }
        }
        guard let apiKey = validatedAPIKey() else { return }

        do {
            let customerInfo: CustomerInfo?
            if !Purchases.isConfigured {
                Purchases.configure(
                    with: Configuration.builder(withAPIKey: apiKey)
                        .with(appUserID: appUserID)
                        .with(entitlementVerificationMode: .informational)
                )
                customerInfo = nil
            } else if Purchases.shared.appUserID == appUserID {
                customerInfo = nil
            } else {
                let loginResult = try await Purchases.shared.logIn(appUserID)
                customerInfo = loginResult.customerInfo
            }

            guard identityCoordinator.isCurrentRequest(context),
                  Purchases.shared.appUserID == appUserID,
                  !Purchases.shared.isAnonymous else {
                MerianLog.general.warning("RevenueCat identity changed before linking completed; ignoring stale result.")
                return
            }

            if request.usesStablePurchasePrincipal {
                // A principal adopted from a legacy Auth-UUID customer may
                // already contain account metadata. Clear it before declaring
                // the shared purchase identity ready for another Auth session.
                Purchases.shared.attribution.setEmail("")
                Purchases.shared.attribution.setDisplayName("")
                Purchases.shared.attribution.setAttributes(
                    RevenueCatStableIdentityPrivacyPolicy.deletionAttributes
                )
                _ = try await Purchases.shared
                    .syncAttributesAndOfferingsIfNeeded()
                guard identityCoordinator.isCurrentRequest(context),
                      Purchases.shared.appUserID == appUserID,
                      !Purchases.shared.isAnonymous else {
                    return
                }
            }

            guard identityCoordinator.commit(context) else { return }

            if let customerInfo {
                updateEntitlements(with: customerInfo)
            } else {
                await refreshCustomerInfo()
            }

            guard isCurrentIdentity(appUserID),
                  identityCoordinator.isCurrentLinkedIdentity(context) else {
                MerianLog.general.warning("RevenueCat identity changed before profile sync completed; ignoring stale result.")
                return
            }

            // Legacy UUID customers retain their existing metadata behavior.
            // Stable principals deliberately carry no account PII.
            if let email = legacyIdentityAttributes?.normalizedEmail {
                Purchases.shared.attribution.setEmail(email)
            }
            if let displayName = legacyIdentityAttributes?.normalizedDisplayName {
                Purchases.shared.attribution.setDisplayName(displayName)
            }
            if let legacyIdentityAttributes {
                Purchases.shared.attribution.setAttributes(
                    legacyIdentityAttributes.subscriberAttributes
                )
            }

            await fetchOfferings()
            MerianLog.general.debug("RevenueCat identity linked.")
        } catch {
            MerianLog.general.debug(
                "RevenueCat identity link failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    // MARK: - Entitlements

    /// Fetches the current customer info and updates entitlement state.
    func refreshCustomerInfo() async {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard let context = currentProviderOperationContext() else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            guard isCurrentProviderOperation(context) else { return }
            updateEntitlements(with: info)
        } catch {
            MerianLog.general.debug(
                "Failed to fetch RevenueCat CustomerInfo; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    private func updateEntitlements(with info: CustomerInfo) {
        guard currentProviderOperationContext() != nil else {
            closePaidReadiness()
            return
        }
        guard RevenueCatCustomerInfoVerificationPolicy.allowsPaidAccess(
            info.entitlements.verification
        ) else {
            isSubscribed = false
            synchronizeFunctionalEntitlement()
            MerianLog.general.error(
                "RevenueCat CustomerInfo failed trusted-entitlement verification; paid access remains closed."
            )
            return
        }

        let isNaturalist = entitlementIsAllowed(
            info.entitlements.all["Naturalist Tier"]
        )
        let isPro = entitlementIsAllowed(info.entitlements.all["pro"])
        let hasActiveStoreBackedSubscription =
            RevenueCatEntitlementProvenancePolicy
                .hasActiveStoreBackedSubscription(
                    productIdentifiers: info.activeSubscriptions,
                    storeByProductIdentifier:
                        info.subscriptionsByProductIdentifier.mapValues(\.store),
                    accountGrantsAllowed:
                        identityCoordinator.accountGrantsAllowed
                )
        let isActive7DayPass = SevenDayPassAccessPolicy.isActive(
            purchases: info.nonSubscriptions.compactMap {
                guard RevenueCatEntitlementProvenancePolicy
                    .allowsStoreBackedAccess(
                        store: $0.store,
                        accountGrantsAllowed:
                            identityCoordinator.accountGrantsAllowed
                    ) else {
                    return nil
                }
                return SevenDayPassPurchase(
                    productIdentifier: $0.productIdentifier,
                    purchaseDate: $0.purchaseDate
                )
            }
        )

        isSubscribed = isNaturalist || isPro ||
            hasActiveStoreBackedSubscription || isActive7DayPass
        synchronizeFunctionalEntitlement()
    }

    private func entitlementIsAllowed(_ entitlement: EntitlementInfo?) -> Bool {
        guard let entitlement, entitlement.isActive else { return false }
        return RevenueCatEntitlementProvenancePolicy.allowsStoreBackedAccess(
            store: entitlement.store,
            accountGrantsAllowed: identityCoordinator.accountGrantsAllowed
        )
    }

    /// Functional Pro is paid RevenueCat access plus current-session server
    /// entitlement. Legacy trial mode is server-owned until cutover; no client
    /// trial window is inferred.
    func synchronizeFunctionalEntitlement() {
        isProActive = !isPurchaseIdentityHandoffPending
            && (
                isSubscribed
                    || EntitlementManager.shared.hasVerifiedFunctionalProAccess
            )
        HardwareOrchestrator.shared.evaluateConstraints()
    }

    /// Fetches available offerings for the paywall.
    func fetchOfferings() async {
        guard !TestExecutionCoordinator.isRunningTests else {
            currentOfferings = nil
            isFetchingOfferings = false
            return
        }
        guard let context = currentProviderOperationContext() else { return }
        isFetchingOfferings = true
        defer {
            let currentContext = currentProviderOperationContext()
            if currentContext == nil || currentContext == context {
                isFetchingOfferings = false
            }
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard isCurrentProviderOperation(context) else { return }
            currentOfferings = offerings

            guard let currentOffering = offerings.current else {
                MerianLog.general.error(
                    "RevenueCat returned no current offering. Select a current offering in the RevenueCat dashboard before release."
                )
                return
            }

            let productIdentifiers = Set(
                currentOffering.availablePackages.map(\.storeProduct.productIdentifier)
            )
            let missingProductIdentifiers = RevenueCatOfferingPolicy.missingRequiredProducts(
                in: productIdentifiers
            )

            if currentOffering.availablePackages.isEmpty {
                MerianLog.general.error(
                    "RevenueCat current offering has no available packages. Verify App Store product readiness and RevenueCat package mapping."
                )
            } else if !missingProductIdentifiers.isEmpty {
                MerianLog.general.error(
                    "RevenueCat current offering is missing required products: \(missingProductIdentifiers.sorted().joined(separator: ","), privacy: .public)"
                )
            }
        } catch {
            MerianLog.general.debug(
                "Failed to fetch RevenueCat offerings; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    /// Clears Auth-session readiness without asking RevenueCat to create an
    /// anonymous customer. Stable purchase principals remain configured and
    /// are rebound by the server for the next Supabase session.
    func handleSupabaseSignOut() async {
        // Invalidate an in-flight SDK mutation. It is deliberately not
        // cancelled: a subsequent identity request queues behind it and repairs
        // the SDK deterministically if the provider call still completes.
        beginPurchaseIdentityResolution()
        identityCoordinator.clearProviderIdentityForSignOutIfLegacy()
        isProActive = false
        EntitlementManager.shared.handleSignOut()
    }

    // MARK: - Purchases

    private func providerMutationContext()
        throws -> RevenueCatProviderOperationContext {
        guard let context = currentProviderOperationContext() else {
            throw RevenueCatManagerError.identityNotReady
        }
        return context
    }

    /// Initiates the purchase flow for `package`.
    func purchase(_ package: Package) async throws {
        let context = try providerMutationContext()
        let result = try await Purchases.shared.purchase(package: package)
        guard isCurrentProviderOperation(context) else { return }
        updateEntitlements(with: result.customerInfo)
    }

    /// Restores previous purchases from Apple.
    func restorePurchases() async throws {
        let context = try providerMutationContext()
        let info = try await Purchases.shared.restorePurchases()
        guard isCurrentProviderOperation(context) else { return }
        updateEntitlements(with: info)
    }

    /// Reposts the current App Store receipt during a trusted, device-durable
    /// identity handoff. This deliberately bypasses only pending-handoff purchase
    /// readiness; exact identity/account kind and captured monotonic generations
    /// must remain current through completion.
    func synchronizePurchasesAfterIdentityHandoff(
        expectedUserId: UUID? = nil
    ) async throws {
        guard let appUserID = linkedAppUserID,
              !usesStablePurchasePrincipal,
              isCurrentProviderMutationIdentity(appUserID) else {
            throw RevenueCatManagerError.identityNotReady
        }
        let matchesExpectedUser = expectedUserId.map {
            RevenueCatAppUserIDPolicy.canonicalID(for: $0) == appUserID
        } ?? true
        guard matchesExpectedUser else {
            throw RevenueCatManagerError.identityNotReady
        }
        let context = identityCoordinator.providerOperationContext(
            appUserID: appUserID
        )
        let info = try await Purchases.shared.syncPurchases()
        let stillMatchesExpectedUser = expectedUserId.map {
            RevenueCatAppUserIDPolicy.canonicalID(for: $0) == appUserID
        } ?? true
        guard identityCoordinator.providerOperationContext(
            appUserID: appUserID
        ) == context,
              isCurrentProviderMutationIdentity(appUserID),
              stillMatchesExpectedUser else {
            throw RevenueCatManagerError.identityNotReady
        }
        updateEntitlements(with: info)
    }

    /// Backward-compatible name for the guest-profile merge caller. The merge
    /// and sign-out protocols share only this exact-identity StoreKit sync.
    func synchronizePurchasesAfterAccountMerge() async throws {
        if usesStablePurchasePrincipal {
            guard let appUserID = linkedAppUserID,
                  identityCoordinator.isPurchaseIdentityReady(
                      providerIdentityReady: isCurrentIdentity(appUserID)
                  ) else {
                throw RevenueCatManagerError.identityNotReady
            }
            return
        }
        try await synchronizePurchasesAfterIdentityHandoff()
    }

    /// Presents Apple's offer-code redemption sheet only for the exact linked
    /// Ghost or permanent Supabase account.
    func presentCodeRedemptionSheet() throws {
        _ = try providerMutationContext()
        Purchases.shared.presentCodeRedemptionSheet()
    }

    /// Presents the App Store subscription management UI or opens the subscriptions settings page.
    func showManageSubscriptions() {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard let context = currentProviderOperationContext() else { return }
        Task { [weak self] in
            guard let self, isCurrentProviderOperation(context) else { return }
            do {
                try await Purchases.shared.showManageSubscriptions()
            } catch {
                guard isCurrentProviderOperation(context) else { return }
                MerianLog.general.debug(
                    "RevenueCat subscription-management presentation failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    _ = await UIApplication.shared.open(url)
                }
            }
        }
    }
}
