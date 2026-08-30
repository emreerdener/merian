import SwiftUI

struct ManagePlanView: View {
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @State private var showPaywall = false
    @State private var viewModel = ManagePlanViewModel()

    private var isShowingOperationError: Binding<Bool> {
        Binding(
            get: { viewModel.operationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.operationErrorMessage = nil
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
                        await viewModel.restorePurchases()
                    }
                } label: {
                    HStack {
                        Text("Restore purchases")
                            .foregroundColor(.primary)
                        Spacer()
                        if viewModel.isRestoring {
                            ProgressView()
                        }
                    }
                }
                .padding(.vertical, 8)
                .disabled(
                    !revenueCatManager.isPurchaseIdentityReady ||
                        viewModel.isRestoring
                )
            } footer: {
                Text("If you've already made a purchase on another device, tap to enable it on this device.")
            }

            Section {
                Button {
                    viewModel.presentCodeRedemption()
                } label: {
                    Text("Redeem code")
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 8)
                .disabled(
                    !revenueCatManager.isPurchaseIdentityReady ||
                        viewModel.isRestoring
                )

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
                viewModel.operationErrorMessage = nil
            }
        } message: {
            Text(viewModel.operationErrorMessage ?? "Please try again.")
        }
    }

}
