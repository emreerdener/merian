import Foundation
import Observation
import os
@_spi(Internal) import RevenueCat

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
        Purchases.logLevel = .warn

        let apiKey = MerianEnvironment.revenueCatApiKey

        #if !DEBUG
        if apiKey.hasPrefix("test_") {
            // RevenueCat throws a fatalError if a "test_" key is used in Release builds.
            // uiPreviewMode prevents the crash in TestFlight but simulates mock products.
            // A real "appl_" key is required for live App Store transactions.
            #warning("TEMPORARY OVERRIDE: Using RevenueCat 'test_' apiKey with uiPreviewMode in Release. Remove before App Store launch!")
            let builder = Configuration.Builder(withAPIKey: apiKey)
                .with(dangerousSettings: DangerousSettings(uiPreviewMode: true))
            Purchases.configure(with: builder.build())
        } else {
            Purchases.configure(withAPIKey: apiKey)
        }
        #else
        Purchases.configure(withAPIKey: apiKey)
        #endif

        Task {
            await refreshCustomerInfo()
            await fetchOfferings()
        }
    }

    // MARK: - Identity

    /// Logs in to RevenueCat with `userId` and syncs optional profile attributes.
    func linkWithSupabase(userId: String, email: String? = nil, displayName: String? = nil, avatarUrl: String? = nil) async {
        guard Purchases.isConfigured else {
            MerianLog.general.warning("RevenueCatManager.linkWithSupabase() skipped: Purchases is not configured.")
            return
        }

        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            updateEntitlements(with: customerInfo)

            // Sync optional profile attributes.
            if let email = email, !email.isEmpty {
                Purchases.shared.attribution.setEmail(email)
            }
            if let displayName = displayName, !displayName.isEmpty {
                Purchases.shared.attribution.setDisplayName(displayName)
            }
            if let avatarUrl = avatarUrl, !avatarUrl.isEmpty {
                Purchases.shared.attribution.setAttributes(["avatar_url": avatarUrl])
            }

            MerianLog.general.debug("RevenueCat login succeeded for user \(userId, privacy: .private)")
        } catch {
            MerianLog.general.debug("RevenueCat login failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Entitlements

    /// Fetches the current customer info and updates entitlement state.
    func refreshCustomerInfo() async {
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
        let is7DayPass   = info.entitlements.all["7_day_pass"]?.isActive == true
        let isPro        = info.entitlements.all["pro"]?.isActive == true
        
        isSubscribed = isNaturalist || is7DayPass || isPro
        
        let diff = Calendar.current.dateComponents([.day], from: info.firstSeen, to: Date()).day ?? 0
        let trialRemaining = max(0, 7 - diff)
        self.trialDaysRemaining = trialRemaining
        
        isProActive = isSubscribed || (trialRemaining > 0)
    }

    /// Fetches available offerings for the paywall.
    func fetchOfferings() async {
        guard Purchases.isConfigured else { return }
        isFetchingOfferings = true
        defer { isFetchingOfferings = false }
        do {
            currentOfferings = try await Purchases.shared.offerings()
        } catch {
            MerianLog.general.debug("Failed to fetch RevenueCat offerings: \(error.localizedDescription, privacy: .private)")
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
}
