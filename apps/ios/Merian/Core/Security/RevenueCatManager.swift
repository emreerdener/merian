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

@MainActor
@Observable final class RevenueCatManager {
    static let shared = RevenueCatManager()
    private init() {
        configure()
    }

    // MARK: - State

    var isProActive: Bool = false
    var isSubscribed: Bool = false
    var trialDaysRemaining: Int?
    
    var currentOfferings: Offerings?
    var isFetchingOfferings: Bool = false

    // MARK: - Configuration

    /// Configures the RevenueCat SDK and fetches initial customer state.
    func configure() {
        guard !TestExecutionCoordinator.isRunningTests else {
            isProActive = false
            isSubscribed = false
            trialDaysRemaining = nil
            currentOfferings = nil
            isFetchingOfferings = false
            return
        }

        Purchases.logLevel = .warn

        let apiKey = MerianEnvironment.revenueCatApiKey
        guard !apiKey.isEmpty else {
            MerianLog.general.error("RevenueCat configuration skipped because REVENUECAT_API_KEY is missing.")
            isProActive = false
            isSubscribed = false
            trialDaysRemaining = nil
            currentOfferings = nil
            isFetchingOfferings = false
            return
        }

        #if !DEBUG
        if apiKey.hasPrefix("test_") {
            MerianLog.general.error("RevenueCat configuration skipped because Release builds require an appl_ production iOS key, not a Test Store key.")
            isProActive = false
            isSubscribed = false
            trialDaysRemaining = nil
            currentOfferings = nil
            isFetchingOfferings = false
            return
        }
        #endif

        Purchases.configure(withAPIKey: apiKey)

        Task {
            await refreshCustomerInfo()
            await fetchOfferings()
        }
    }

    // MARK: - Identity

    /// Logs in to RevenueCat with `userId` and syncs optional profile attributes.
    func linkWithSupabase(
        userId: String,
        email: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        publicUsername: String? = nil,
        publicAuthorName: String? = nil,
        publicIdentitySource: String? = nil,
        accountKind: String? = nil
    ) async {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard Purchases.isConfigured else {
            MerianLog.general.warning("RevenueCatManager.linkWithSupabase() skipped: Purchases is not configured.")
            return
        }

        let identity = RevenueCatIdentityContext(
            userId: userId,
            email: email,
            displayName: displayName,
            avatarUrl: avatarUrl,
            publicUsername: publicUsername,
            publicAuthorName: publicAuthorName,
            publicIdentitySource: publicIdentitySource,
            accountKind: accountKind
        )

        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            updateEntitlements(with: customerInfo)

            // Sync optional profile attributes.
            if let email = identity.normalizedEmail {
                Purchases.shared.attribution.setEmail(email)
            }
            if let displayName = identity.normalizedDisplayName {
                Purchases.shared.attribution.setDisplayName(displayName)
            }
            Purchases.shared.attribution.setAttributes(identity.subscriberAttributes)

            MerianLog.general.debug("RevenueCat login succeeded for user \(userId, privacy: .private)")
        } catch {
            MerianLog.general.debug("RevenueCat login failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Entitlements

    /// Fetches the current customer info and updates entitlement state.
    func refreshCustomerInfo() async {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            updateEntitlements(with: info)
        } catch {
            MerianLog.general.debug("Failed to fetch customer info: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func updateEntitlements(with info: CustomerInfo) {
        let isNaturalist = info.entitlements.all["Naturalist Tier"]?.isActive == true
        let isPro        = info.entitlements.all["pro"]?.isActive == true
        let isActive7DayPass = SevenDayPassAccessPolicy.isActive(
            purchases: info.nonSubscriptions.map {
                SevenDayPassPurchase(
                    productIdentifier: $0.productIdentifier,
                    purchaseDate: $0.purchaseDate
                )
            }
        )
        
        isSubscribed = isNaturalist || isPro || isActive7DayPass
        
        let diff = Calendar.current.dateComponents([.day], from: info.firstSeen, to: Date()).day ?? 0
        let trialRemaining = max(0, 7 - diff)
        self.trialDaysRemaining = trialRemaining
        
        isProActive = isSubscribed || (trialRemaining > 0)
    }

    /// Fetches available offerings for the paywall.
    func fetchOfferings() async {
        guard !TestExecutionCoordinator.isRunningTests else {
            currentOfferings = nil
            isFetchingOfferings = false
            return
        }
        guard Purchases.isConfigured else { return }
        isFetchingOfferings = true
        defer { isFetchingOfferings = false }
        do {
            let offerings = try await Purchases.shared.offerings()
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

    /// Clears local entitlement state and logs out the SDK when appropriate.
    func handleSupabaseSignOut() async {
        isProActive = false
        isSubscribed = false
        trialDaysRemaining = nil

        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard Purchases.isConfigured else { return }

        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            MerianLog.general.debug("RevenueCat logOut failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Purchases

    /// Initiates the purchase flow for `package`.
    func purchase(_ package: Package) async throws {
        guard Purchases.isConfigured else {
            throw NSError(domain: "RevenueCatManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Purchases not configured."])
        }
        let result = try await Purchases.shared.purchase(package: package)
        updateEntitlements(with: result.customerInfo)
    }

    /// Restores previous purchases from Apple.
    func restorePurchases() async throws {
        guard Purchases.isConfigured else {
            throw NSError(domain: "RevenueCatManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Purchases not configured."])
        }
        let info = try await Purchases.shared.restorePurchases()
        updateEntitlements(with: info)
    }

    /// Presents the App Store subscription management UI or opens the subscriptions settings page.
    func showManageSubscriptions() {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard Purchases.isConfigured else { return }
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
