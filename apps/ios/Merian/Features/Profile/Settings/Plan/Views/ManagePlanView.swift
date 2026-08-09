import SwiftUI

struct ManagePlanView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var operationErrorMessage: String?

    private var isShowingOperationError: Binding<Bool> {
        Binding(
            get: { operationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    operationErrorMessage = nil
                }
            }
        )
    }

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
                        defer { isRestoring = false }
                        do {
                            try await revenueCatManager.restorePurchases()
                        } catch {
                            operationErrorMessage = error.localizedDescription
                            MerianLog.general.error("Failed to restore purchases: \(error.localizedDescription, privacy: .private)")
                        }
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
                .disabled(!revenueCatManager.isPurchaseIdentityReady || isRestoring)
            } footer: {
                Text("If you've already made a purchase on another device, tap to enable it on this device.")
            }
            
            Section {
                Button {
                    do {
                        try revenueCatManager.presentCodeRedemptionSheet()
                    } catch {
                        operationErrorMessage = error.localizedDescription
                        MerianLog.general.error("Failed to present code redemption: \(error.localizedDescription, privacy: .private)")
                    }
                } label: {
                    Text("Redeem code")
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 8)
                .disabled(!revenueCatManager.isPurchaseIdentityReady)
                
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
        .alert("Unable to Complete Purchase", isPresented: isShowingOperationError) {
            Button("OK", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "Please try again.")
        }
    }
    
}
