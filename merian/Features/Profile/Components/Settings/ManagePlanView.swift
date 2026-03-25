import SwiftUI
import RevenueCat

struct ManagePlanView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @State private var showPaywall = false
    @State private var isRestoring = false

    var body: some View {
        List {
            PlanCard(showPaywall: $showPaywall)
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
            } footer: {
                Text("If you've already made a purchase on another device, tap to enable it on this device.")
            }
            
            Section {
                Button {
                    Purchases.shared.presentCodeRedemptionSheet()
                } label: {
                    Text("Redeem code")
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 8)
                
                if let termsUrl = URL(string: "https://example.com/terms") {
                    Link("Terms of service", destination: termsUrl)
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                }
                
                if let privacyUrl = URL(string: "https://example.com/privacy") {
                    Link("Privacy policy", destination: privacyUrl)
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Upgrade")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(revenueCatManager)
        }
    }
    

}
