import SwiftUI
import RevenueCat

struct PaywallFeature {
    let icon: String
    let title: String
    let description: String
}

let proFeatures = [
    PaywallFeature(icon: "infinity", title: "Unlimited Scans", description: "Identify species continuously without daily scan limits."),
    PaywallFeature(icon: "sparkles", title: "Pro AI Vision", description: "Access our most advanced, diagnostic-grade AI model."),
    PaywallFeature(icon: "waveform", title: "Audio Recording", description: "Identify birds and insects by their distinct calls."),
    PaywallFeature(icon: "square.stack.3d.up", title: "Multi-Capture Mode", description: "Upload multiple images or audio to help identify."),
    PaywallFeature(icon: "leaf.arrow.triangle.circlepath", title: "Ecological Telemetry", description: "Unlock deep dive insights like size and interactions.")
]

struct PaywallView: View {
    @Environment(RevenueCatManager.self) var revenueCatManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .padding(24)
                        .background(
                            Circle()
                                .fill(Color.green.opacity(0.1))
                        )
                        .padding(.bottom, 8)

                    Text("Merian Pro")
                        .font(.system(.largeTitle, design: .serif))
                        .fontWeight(.bold)

                    Text("Unlock the full power of our AI and explore the wilderness without limits.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Features
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(proFeatures, id: \.title) { feature in
                        HStack(spacing: 16) {
                            Image(systemName: feature.icon)
                                .font(.title2)
                                .foregroundColor(.green)
                                .frame(width: 36)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title)
                                    .font(.headline)
                                Text(feature.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)

                // Subscriptions
                if revenueCatManager.isFetchingOfferings {
                    ProgressView("Loading packs...")
                        .padding(.top, 40)
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
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }

                Spacer(minLength: 24)

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                    }
                }
            }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
    }
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
    
    @State private var shimmerPhase: CGFloat = -0.5

    private var titleText: String {
        switch package.packageType {
        case .annual: return "Naturalist Tier"
        case .weekly: return "7-Day Pass"
        case .monthly: return "Explorer Tier"
        case .lifetime: return "Lifetime Access"
        default: return package.storeProduct.localizedTitle
        }
    }
    
    private var subtitleText: String {
        switch package.packageType {
        case .annual: return "Yearly subscription"
        case .weekly: return "One week of Pro features"
        case .monthly: return "Monthly subscription"
        case .lifetime: return "Pay once, keep forever"
        default: return package.storeProduct.localizedDescription
        }
    }

    var body: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(titleText)
                            .font(.headline)
                            .foregroundColor(.primary)
                            
                        if package.packageType == .annual {
                            Text("BEST VALUE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(package.storeProduct.localizedPriceString)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.40, blue: 0.25), Color(red: 0.12, green: 0.65, blue: 0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: shimmerPhase - 0.2),
                                        .init(color: .white.opacity(0.9), location: shimmerPhase),
                                        .init(color: .clear, location: shimmerPhase + 0.2)
                                    ],
                                    startPoint: .bottomTrailing,
                                    endPoint: .topLeading
                                ),
                                lineWidth: 1.5
                            )
                    )
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.green.opacity(package.packageType == .annual ? 0.3 : 0), lineWidth: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: shimmerPhase - 0.2),
                                .init(color: .green.opacity(0.6), location: shimmerPhase),
                                .init(color: .clear, location: shimmerPhase + 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2.0).delay(3.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.5
            }
        }
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
