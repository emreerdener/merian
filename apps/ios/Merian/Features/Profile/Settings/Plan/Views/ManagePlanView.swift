import SwiftUI

struct ManagePlanView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @State private var showPaywall = false
    @State private var isRestoring = false

    var body: some View {
        List {
            PlanCard(
                showPaywall: $showPaywall,
                complimentaryDetailContext: .settings
            )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            Section {
                Button {
                    Task {
                        isRestoring = true
                        do {
                            try await revenueCatManager.restorePurchases()
                        } catch {
                            MerianLog.general.error("Failed to restore purchases: \(error.localizedDescription, privacy: .public)")
                        }
                        isRestoring = false
                    }
                } label: {
                    HStack {
                        Text("Restore purchases")
                            .foregroundColor(.primary)
                        Spacer()
                        if isRestoring {
                            ProgressView()
                        }
                    }
                }
                .padding(.vertical, 8)
                .disabled(!revenueCatManager.isIdentityReady || isRestoring)
            } footer: {
                Text("If you've already made a purchase on another device, tap to enable it on this device.")
            }
            
            Section {
                Button {
                    revenueCatManager.presentCodeRedemptionSheet()
                } label: {
                    Text("Redeem code")
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 8)
                .disabled(!revenueCatManager.isIdentityReady)
                
                Link("Terms of service", destination: PublicBrand.websiteURL(path: "terms"))
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
                
                Link("Privacy policy", destination: PublicBrand.websiteURL(path: "privacy"))
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(revenueCatManager.isProActive ? "Plan" : "Upgrade")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(revenueCatManager)
        }
    }
    
}
