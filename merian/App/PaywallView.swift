import SwiftUI
import RevenueCat

struct PaywallView: View {
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header / Hero
                VStack(spacing: 12) {
                    Image(systemName: "leaf.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.green)
                    
                    Text("Unlock the Wilderness")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("You've used your 3 free Daily Scans. Keep exploring without limits by choosing a plan below.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)
                
                // Active Packages Loading State
                if revenueCatManager.isFetchingOfferings {
                    ProgressView("Loading regional packs...")
                        .padding(.top, 50)
                } else if let offerings = revenueCatManager.currentOfferings {
                    // Display specifically the 'current' designated packages
                    VStack(spacing: 16) {
                        if let currentOffering = offerings.current {
                            ForEach(currentOffering.availablePackages) { package in
                                PackageCardButton(package: package)
                            }
                        } else {
                            Text("No subscriptions currently available.")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Footer Buttons (Restore / Terms)
                HStack(spacing: 24) {
                    Button(action: {
                        Task { await tryRestore() }
                    }) {
                        Text("Restore Purchases")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 30)
            }
        }
        .presentationBackground(.thinMaterial)
        .environment(\.colorScheme, .dark)
    }
    
    // Safely trigger restore binding securely inside the Paywall
    private func tryRestore() async {
        do {
            try await revenueCatManager.restorePurchases()
            if revenueCatManager.isProActive {
                dismiss() // Automatically drop the paywall instantly on a live restore
            }
        } catch {
            print("Failed to restore Apple IDs: \(error)")
        }
    }
}

// SwiftUI UI Representation isolating the structural Package button
struct PackageCardButton: View {
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @Environment(\.dismiss) var dismiss
    
    let package: Package
    
    var body: some View {
        Button(action: {
            Task {
                do {
                    try await revenueCatManager.purchase(package)
                    if revenueCatManager.isProActive {
                        dismiss() // The purchase succeeded, tear down the wall!
                    }
                } catch {
                    print("Apple In-App Checkout Failed: \(error.localizedDescription)")
                }
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(package.storeProduct.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Text(package.storeProduct.localizedPriceString)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.green.opacity(0.8))
                    .clipShape(Capsule())
            }
            .padding()
            .background(Color(white: 0.15))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
