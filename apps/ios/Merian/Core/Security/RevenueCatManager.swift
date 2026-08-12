import Observation
import os
@_spi(Internal) import RevenueCat
import UIKit

struct SevenDayPassPurchase {
    let productIdentifier: String
    let purchaseDate: Date
}

enum SevenDayPassAccessPolicy {
    static let productIdentifier = "pro_week"
    static let duration: TimeInterval = 7 * 24 * 60 * 60

    static func isActive(
        purchases: [SevenDayPassPurchase],
        now: Date = Date()
    ) -> Bool {
        purchases.contains { purchase in
            guard purchase.productIdentifier == productIdentifier else { return false }
            return purchase.purchaseDate.addingTimeInterval(duration) > now
        }
    }
}

enum RevenueCatOfferingPolicy {
    static let annualProductIdentifier = "pro_annual"
    static let requiredProductIdentifiers = Set([
        SevenDayPassAccessPolicy.productIdentifier,
        annualProductIdentifier
    ])

    static func missingRequiredProducts(in productIdentifiers: Set<String>) -> Set<String> {
        requiredProductIdentifiers.subtracting(productIdentifiers)
    }
}

enum RevenueCatAppUserIDPolicy {
    /// RevenueCat App User IDs are case-sensitive. Merian uses the uppercase
    /// RFC 4122 representation emitted by Swift as the single cross-system ID.
    static func canonicalID(for userID: UUID) -> String {
        userID.uuidString.uppercased()
    }
}

enum RevenueCatAccountMutationPolicy {
    static let ghostAccountKind = "anonymous"
    static let permanentAccountKind = "authenticated"

    static func accountKind(isAnonymous: Bool) -> String {
        isAnonymous ? ghostAccountKind : permanentAccountKind
    }

    static func normalizedAccountKind(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    static func allowsProviderMutation(accountKind: String?) -> Bool {
        switch normalizedAccountKind(accountKind) {
        case ghostAccountKind, permanentAccountKind:
            return true
        default:
            return false
        }
    }

    static func isReady(
        identityReady: Bool,
        requestedAccountKind: String?,
        linkedAccountKind: String?
    ) -> Bool {
        let requested = normalizedAccountKind(requestedAccountKind)
        let linked = normalizedAccountKind(linkedAccountKind)
        return identityReady
            && requested == linked
            && allowsProviderMutation(accountKind: linked)
    }
}

enum RevenueCatPurchaseMutationPolicy {
    static func isReady(
        providerIdentityReady: Bool,
        identityHandoffPending: Bool
    ) -> Bool {
        providerIdentityReady && !identityHandoffPending
    }
}

enum RevenueCatEntitlementProvenancePolicy {
    static func hasActiveStoreBackedSubscription(
        productIdentifiers: Set<String>
    ) -> Bool {
        productIdentifiers.contains(
            RevenueCatOfferingPolicy.annualProductIdentifier
        )
    }

    static func allowsStoreBackedAccess(
        store: Store,
        accountGrantsAllowed: Bool
    ) -> Bool {
        if accountGrantsAllowed { return true }
        switch store {
        case .appStore, .macAppStore, .testStore:
            return true
        default:
            return false
        }
    }
}

enum RevenueCatManagerError: LocalizedError {
    case identityNotReady

    var errorDescription: String? {
        switch self {
        case .identityNotReady:
            return "RevenueCat is waiting for the active Merian account. Please try again."
        }
    }
}

struct RevenueCatIdentityContext: Equatable {
    let userId: String
    let email: String?
    let displayName: String?
    let avatarUrl: String?
    let publicUsername: String?
    let publicAuthorName: String?
    let publicIdentitySource: String?
    let accountKind: String?

    var normalizedEmail: String? {
        Self.normalized(email)
    }

    var normalizedDisplayName: String? {
        if let displayName = Self.firstNonEmpty(displayName, publicAuthorName) {
            return displayName
        }
        guard let publicUsername = Self.normalized(publicUsername) else { return nil }
        return "@\(publicUsername)"
    }

    var subscriberAttributes: [String: String] {
        var attributes: [String: String] = [
            "supabase_user_id": userId
        ]

        set("auth_email", email, in: &attributes)
        set("display_name", normalizedDisplayName, in: &attributes)
        set("avatar_url", avatarUrl, in: &attributes)
        set("public_username", publicUsername, in: &attributes)
        set("public_author_name", publicAuthorName, in: &attributes)
        set("public_identity_source", publicIdentitySource, in: &attributes)
        set("account_kind", accountKind, in: &attributes)

        return attributes
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap(normalized).first
    }

    private func set(_ key: String, _ value: String?, in attributes: inout [String: String]) {
        guard let normalized = Self.normalized(value) else { return }
        attributes[key] = normalized
    }
}

enum RevenueCatStableIdentityPrivacyPolicy {
    static let legacyAccountAttributeKeys = [
        "supabase_user_id",
        "auth_email",
        "display_name",
        "avatar_url",
        "public_username",
        "public_author_name",
        "public_identity_source",
        "account_kind"
    ]

    static var deletionAttributes: [String: String] {
        Dictionary(uniqueKeysWithValues: legacyAccountAttributeKeys.map {
            ($0, "")
        })
    }
}

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
        isSubscribed || EntitlementManager.shared.canStartProFundedScan
    }
    
    var currentOfferings: Offerings?
    var isFetchingOfferings: Bool = false

    private(set) var linkedAppUserID: String?
    private var requestedAppUserID: String?
    private(set) var linkedAuthUserID: UUID?
    private var requestedAuthUserID: UUID?
    private(set) var linkedBindingGeneration: Int64?
    private var requestedBindingGeneration: Int64?
    private(set) var usesStablePurchasePrincipal = false
    private var accountGrantsAllowed = true
    private(set) var linkedAccountKind: String?
    private var requestedAccountKind: String?
    @ObservationIgnored private var identityLinkTask: Task<Void, Never>?
    @ObservationIgnored private var identityLinkTaskId: UUID?
    private var identityRequestGeneration: UInt64 = 0
    /// A device-durable StoreKit identity transfer is unresolved. RevenueCat
    /// may already be linked to the destination, but user-initiated provider
    /// mutations remain disabled until the server verifies continuity.
    private(set) var isPurchaseIdentityHandoffPending = false

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
        return RevenueCatPurchaseMutationPolicy.isReady(
            providerIdentityReady: isCurrentProviderMutationIdentity(linkedAppUserID),
            identityHandoffPending: isPurchaseIdentityHandoffPending
        )
    }

    func setPurchaseIdentityHandoffPending(_ pending: Bool) {
        isPurchaseIdentityHandoffPending = pending
    }

    /// Closes provider mutation readiness before an asynchronous server mode
    /// decision. A resolver timeout, rollback response, or stale Auth result
    /// must not leave the previous RevenueCat customer usable merely because
    /// the SDK is still configured to it. The next successful exact binding
    /// reopens readiness without creating an anonymous provider customer.
    func beginPurchaseIdentityResolution() {
        identityRequestGeneration &+= 1
        requestedAppUserID = nil
        requestedAuthUserID = nil
        requestedBindingGeneration = nil
        requestedAccountKind = nil
        linkedAuthUserID = nil
        linkedBindingGeneration = nil
        linkedAccountKind = nil
        accountGrantsAllowed = false
        isSubscribed = false
        currentOfferings = nil
        isFetchingOfferings = false
        synchronizeFunctionalEntitlement()
    }

    private func isCurrentIdentity(_ appUserID: String) -> Bool {
        guard !TestExecutionCoordinator.isRunningTests,
              Purchases.isConfigured,
              requestedAppUserID == appUserID,
              linkedAppUserID == appUserID,
              requestedAuthUserID == linkedAuthUserID,
              requestedBindingGeneration == linkedBindingGeneration else {
            return false
        }

        return !Purchases.shared.isAnonymous && Purchases.shared.appUserID == appUserID
    }

    private func isCurrentProviderMutationIdentity(_ appUserID: String) -> Bool {
        RevenueCatAccountMutationPolicy.isReady(
            identityReady: isCurrentIdentity(appUserID),
            requestedAccountKind: requestedAccountKind,
            linkedAccountKind: linkedAccountKind
        )
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
        identityRequestGeneration &+= 1
        let requestGeneration = identityRequestGeneration
        requestedAppUserID = appUserID
        requestedAuthUserID = authUserID
        requestedBindingGeneration = bindingGeneration
        requestedAccountKind = normalizedAccountKind

        if linkedAppUserID != appUserID {
            linkedAppUserID = nil
            linkedAuthUserID = nil
            linkedBindingGeneration = nil
            linkedAccountKind = nil
            isSubscribed = false
            currentOfferings = nil
            synchronizeFunctionalEntitlement()
        } else if linkedAuthUserID != authUserID
                    || linkedBindingGeneration != bindingGeneration
                    || linkedAccountKind != normalizedAccountKind {
            // Fail closed while the same provider customer is rebound to a new
            // Auth session or account kind.
            linkedAuthUserID = nil
            linkedBindingGeneration = nil
            linkedAccountKind = nil
        }

        // RevenueCat SDK identity mutations are asynchronous and are not
        // guaranteed to stop when their caller is cancelled. Serialize them so
        // an older login cannot finish after a newer Auth event and leave the
        // SDK on the stale customer. The newest request always runs last.
        let previousTask = identityLinkTask
        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            if let previousTask {
                await previousTask.value
            }
            guard let self,
                  self.identityRequestGeneration == requestGeneration else {
                return
            }
            await self.performIdentityLink(
                appUserID: appUserID,
                authUserID: authUserID,
                bindingGeneration: bindingGeneration,
                accountKind: normalizedAccountKind,
                accountGrantsAllowed: accountGrantsAllowed,
                stablePurchasePrincipal: stablePurchasePrincipal,
                legacyIdentityAttributes: legacyIdentityAttributes,
                requestGeneration: requestGeneration
            )
        }
        identityLinkTask = task
        identityLinkTaskId = taskId
        await task.value
        if identityLinkTaskId == taskId {
            identityLinkTask = nil
            identityLinkTaskId = nil
        }
    }

    private func performIdentityLink(
        appUserID: String,
        authUserID: UUID,
        bindingGeneration: Int64,
        accountKind normalizedAccountKind: String?,
        accountGrantsAllowed: Bool,
        stablePurchasePrincipal: Bool,
        legacyIdentityAttributes: RevenueCatIdentityContext?,
        requestGeneration: UInt64
    ) async {
        guard identityRequestGeneration == requestGeneration,
              requestedAppUserID == appUserID,
              requestedAuthUserID == authUserID,
              requestedBindingGeneration == bindingGeneration,
              requestedAccountKind == normalizedAccountKind else {
            return
        }

        Purchases.logLevel = .warn
        guard let apiKey = validatedAPIKey() else { return }

        do {
            let customerInfo: CustomerInfo?
            if !Purchases.isConfigured {
                Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
                customerInfo = nil
            } else if Purchases.shared.appUserID == appUserID {
                customerInfo = nil
            } else {
                let loginResult = try await Purchases.shared.logIn(appUserID)
                customerInfo = loginResult.customerInfo
            }

            guard requestedAppUserID == appUserID,
                  requestedAuthUserID == authUserID,
                  requestedBindingGeneration == bindingGeneration,
                  requestedAccountKind == normalizedAccountKind,
                  identityRequestGeneration == requestGeneration,
                  Purchases.shared.appUserID == appUserID,
                  !Purchases.shared.isAnonymous else {
                MerianLog.general.warning("RevenueCat identity changed before linking completed; ignoring stale result.")
                return
            }

            if stablePurchasePrincipal {
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
                guard requestedAppUserID == appUserID,
                      requestedAuthUserID == authUserID,
                      requestedBindingGeneration == bindingGeneration,
                      requestedAccountKind == normalizedAccountKind,
                      identityRequestGeneration == requestGeneration,
                      Purchases.shared.appUserID == appUserID,
                      !Purchases.shared.isAnonymous else {
                    return
                }
            }

            linkedAppUserID = appUserID
            linkedAuthUserID = authUserID
            linkedBindingGeneration = bindingGeneration
            linkedAccountKind = normalizedAccountKind
            usesStablePurchasePrincipal = stablePurchasePrincipal
            self.accountGrantsAllowed = accountGrantsAllowed

            if let customerInfo {
                updateEntitlements(with: customerInfo)
            } else {
                await refreshCustomerInfo()
            }

            guard isCurrentIdentity(appUserID),
                  linkedAuthUserID == authUserID,
                  linkedBindingGeneration == bindingGeneration,
                  identityRequestGeneration == requestGeneration,
                  requestedAccountKind == normalizedAccountKind,
                  linkedAccountKind == normalizedAccountKind else {
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
            MerianLog.general.debug("RevenueCat identity linked for user \(appUserID, privacy: .private)")
        } catch {
            MerianLog.general.debug("RevenueCat identity link failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Entitlements

    /// Fetches the current customer info and updates entitlement state.
    func refreshCustomerInfo() async {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard let appUserID = linkedAppUserID,
              isCurrentIdentity(appUserID) else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            guard isCurrentIdentity(appUserID) else { return }
            updateEntitlements(with: info)
        } catch {
            MerianLog.general.debug("Failed to fetch customer info: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func updateEntitlements(with info: CustomerInfo) {
        let isNaturalist = entitlementIsAllowed(
            info.entitlements.all["Naturalist Tier"]
        )
        let isPro = entitlementIsAllowed(info.entitlements.all["pro"])
        let hasActiveStoreBackedSubscription =
            RevenueCatEntitlementProvenancePolicy
                .hasActiveStoreBackedSubscription(
                    productIdentifiers: info.activeSubscriptions
                )
        let isActive7DayPass = SevenDayPassAccessPolicy.isActive(
            purchases: info.nonSubscriptions.compactMap {
                guard RevenueCatEntitlementProvenancePolicy
                    .allowsStoreBackedAccess(
                        store: $0.store,
                        accountGrantsAllowed: accountGrantsAllowed
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
            accountGrantsAllowed: accountGrantsAllowed
        )
    }

    /// Functional Pro is paid RevenueCat access plus current-session server
    /// entitlement. Legacy trial mode is server-owned until cutover; no client
    /// trial window is inferred.
    func synchronizeFunctionalEntitlement() {
        isProActive = isSubscribed || EntitlementManager.shared.hasVerifiedFunctionalProAccess
        HardwareOrchestrator.shared.evaluateConstraints()
    }

    /// Fetches available offerings for the paywall.
    func fetchOfferings() async {
        guard !TestExecutionCoordinator.isRunningTests else {
            currentOfferings = nil
            isFetchingOfferings = false
            return
        }
        guard let appUserID = linkedAppUserID,
              isCurrentIdentity(appUserID) else { return }
        isFetchingOfferings = true
        defer {
            if requestedAppUserID == appUserID {
                isFetchingOfferings = false
            }
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard isCurrentIdentity(appUserID) else { return }
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
            MerianLog.general.debug("Failed to fetch RevenueCat offerings: \(error.localizedDescription, privacy: .private)")
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
        if !usesStablePurchasePrincipal {
            linkedAppUserID = nil
        }
        isProActive = false
        EntitlementManager.shared.handleSignOut()
    }

    // MARK: - Purchases

    private func providerMutationAppUserID() throws -> String {
        guard let appUserID = linkedAppUserID,
              isCurrentProviderMutationIdentity(appUserID),
              !isPurchaseIdentityHandoffPending else {
            throw RevenueCatManagerError.identityNotReady
        }
        return appUserID
    }

    /// Initiates the purchase flow for `package`.
    func purchase(_ package: Package) async throws {
        let appUserID = try providerMutationAppUserID()
        let result = try await Purchases.shared.purchase(package: package)
        guard isCurrentProviderMutationIdentity(appUserID) else { return }
        updateEntitlements(with: result.customerInfo)
    }

    /// Restores previous purchases from Apple.
    func restorePurchases() async throws {
        let appUserID = try providerMutationAppUserID()
        let info = try await Purchases.shared.restorePurchases()
        guard isCurrentProviderMutationIdentity(appUserID) else { return }
        updateEntitlements(with: info)
    }

    /// Reposts the current App Store receipt during a trusted, device-durable
    /// identity handoff. This deliberately bypasses only the user-purchase
    /// mutation fence; the exact canonical RevenueCat identity and account
    /// kind must already match the active Supabase session.
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
        let info = try await Purchases.shared.syncPurchases()
        let stillMatchesExpectedUser = expectedUserId.map {
            RevenueCatAppUserIDPolicy.canonicalID(for: $0) == appUserID
        } ?? true
        guard isCurrentProviderMutationIdentity(appUserID),
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
                  isCurrentProviderMutationIdentity(appUserID),
                  !isPurchaseIdentityHandoffPending else {
                throw RevenueCatManagerError.identityNotReady
            }
            return
        }
        try await synchronizePurchasesAfterIdentityHandoff()
    }

    /// Presents Apple's offer-code redemption sheet only for the exact linked
    /// Ghost or permanent Supabase account.
    func presentCodeRedemptionSheet() throws {
        _ = try providerMutationAppUserID()
        Purchases.shared.presentCodeRedemptionSheet()
    }

    /// Presents the App Store subscription management UI or opens the subscriptions settings page.
    func showManageSubscriptions() {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard isIdentityReady else { return }
        Task {
            do {
                try await Purchases.shared.showManageSubscriptions()
            } catch {
                MerianLog.general.debug("Purchases.showManageSubscriptions failed: \(error.localizedDescription, privacy: .private)")
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    _ = await UIApplication.shared.open(url)
                }
            }
        }
    }
}
