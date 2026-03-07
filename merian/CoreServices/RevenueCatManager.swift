import Foundation
import RevenueCat

@MainActor
final class RevenueCatManager: ObservableObject {
    static let shared = RevenueCatManager()
    
    @Published var isProActive: Bool = false
    @Published var currentOfferings: Offerings?
    @Published var isFetchingOfferings: Bool = false
    
    private init() {}
    
    /// Initializes checking RevenueCat for active telemetry tokens
    func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: MerianEnvironment.revenueCatApiKey)
        
        Task {
            await refreshCustomerInfo()
            await fetchOfferings()
        }
    }
    
    /// Establishes the link between RevenueCat's UUID constraint and the Supabase Ghost User UUID 
    func linkWithSupabase(userId: String) async {
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)
            self.updateEntitlements(with: customerInfo)
            print("🚀 Successfully linked RevenueCat UUID to Supabase Identity: \(userId)")
        } catch {
            print("⚠️ RevenueCat login failed: \(error.localizedDescription)")
        }
    }
    
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
        let isWeekendWarrior = info.entitlements.all["Weekend Warrior Pass"]?.isActive == true
        
        self.isProActive = isNaturalist || isWeekendWarrior
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
