import Foundation
@_spi(Internal) import RevenueCat
import Observation

// MARK: - Core Subscription Engine
@MainActor
@Observable final class RevenueCatManager {
    // MARK: - Singleton Architecture
    static let shared = RevenueCatManager()
    private init() {}
    
    // MARK: - State Management
    var isProActive: Bool = false
    var currentOfferings: Offerings?
    var isFetchingOfferings: Bool = false
    
    // MARK: - Component Initialization
    /// Initializes checking RevenueCat for active telemetry tokens
    func configure() {
        Purchases.logLevel = .debug
        
        let apiKey = MerianEnvironment.revenueCatApiKey
        
        // Allow the environment to dictate the exact key used directly. 
        // If a test_ key is provided locally or via Xcode Cloud, RevenueCat will safely initialize in Sandbox mode natively.
        
        #if !DEBUG
        if apiKey.hasPrefix("test_") {
            #warning("TEMPORARY OVERRIDE: Using RevenueCat 'test_' apiKey with uiPreviewMode in Release. Remove before App Store launch!")
            // RevenueCat intrinsically throws a fatalError if a "test_" API key is used in Release builds.
            // Bypassing with uiPreviewMode guarantees the app won't crash on boot in TestFlight, but it will
            // simulate mock products. A real App Store ("appl_") key is required for actual TestFlight interactions.
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
    
    // MARK: - Identity Synchronization
    /// Establishes the link between RevenueCat's UUID constraint and the Supabase Identity, synchronizing optional User Metadata 
    func linkWithSupabase(userId: String, email: String? = nil, displayName: String? = nil, avatarUrl: String? = nil) async {
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            self.updateEntitlements(with: customerInfo)
            
            // Push Standardized Auth Metrics directly to RevenueCat profiles
            if let email = email, !email.isEmpty {
                Purchases.shared.attribution.setEmail(email)
            }
            if let displayName = displayName, !displayName.isEmpty {
                Purchases.shared.attribution.setDisplayName(displayName)
            }
            if let avatarUrl = avatarUrl, !avatarUrl.isEmpty {
                Purchases.shared.attribution.setAttributes(["avatar_url": avatarUrl])
            }
            
            print("🚀 Successfully linked RevenueCat UUID to Supabase Identity: \(userId)")
        } catch {
            print("⚠️ RevenueCat login failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Entitlement Processing
    /// Evaluates if the user actively holds the `Naturalist` or `Weekend Warrior` pass bounds
    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            self.updateEntitlements(with: info)
        } catch {
            print("Failed to fetch customer info: \(error.localizedDescription)")
        }
    }
    
    private func updateEntitlements(with info: CustomerInfo) {
        // Enforcing the Master Protocol tiers
        let isNaturalist = info.entitlements.all["Naturalist Tier"]?.isActive == true
        let is7DayPass = info.entitlements.all["7_day_pass"]?.isActive == true
        let isPro = info.entitlements.all["pro"]?.isActive == true
        
        self.isProActive = isNaturalist || is7DayPass || isPro
    }
    
    /// Fetches all active packages available for the Paywall rendering UI
    func fetchOfferings() async {
        self.isFetchingOfferings = true
        defer { self.isFetchingOfferings = false }
        
        do {
            self.currentOfferings = try await Purchases.shared.offerings()
        } catch {
            print("⚠️ Failed to fetch RevenueCat Offerings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Native Apple Transactions
    /// Safely triggers the Apple native checkout sheet locking into RevenueCat asynchronously
    func purchase(_ package: Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)
        self.updateEntitlements(with: result.customerInfo)
    }
    
    /// Restores any missing transactions from Apple back into the device boundary
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        self.updateEntitlements(with: info)
    }
}
