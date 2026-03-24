import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(RevenueCatManager.self) var revenueCatManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "leaf.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.green)

                    Text("Unlock the wilderness")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("You've used your 2 free daily scans. Keep exploring without limits by choosing an option below.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                if revenueCatManager.isFetchingOfferings {
                    ProgressView("Loading regional packs...")
                        .padding(.top, 50)
                } else if let offerings = revenueCatManager.currentOfferings {
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

                // Footer
                HStack(spacing: 24) {
                    Button("Restore purchases") {
                        Task { await tryRestore() }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Button("Redeem code") {
                        Purchases.shared.presentCodeRedemptionSheet()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if let termsUrl = URL(string: "https://example.com/terms") {
                        Link("Terms of service", destination: termsUrl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
    }

    // MARK: - Actions

    private func tryRestore() async {
        do {
            try await revenueCatManager.restorePurchases()
            if revenueCatManager.isProActive {
                dismiss()
            }
        } catch {
            MerianLog.general.error("Purchase restore failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct PackageCardButton: View {
    @Environment(RevenueCatManager.self) var revenueCatManager
    @Environment(\.dismiss) var dismiss

    let package: Package

    var body: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(package.storeProduct.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Actions

    private func purchase() async {
        do {
            try await revenueCatManager.purchase(package)
            if revenueCatManager.isProActive {
                dismiss()
            }
        } catch {
            MerianLog.general.error("In-app purchase failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
