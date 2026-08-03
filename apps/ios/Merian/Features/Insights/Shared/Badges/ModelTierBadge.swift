import SwiftUI

struct ModelTierBadge: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    var label: String = "Upgrade for advanced analysis"
    
    @State private var showPaywall: Bool = false
    @State private var entitlement = EntitlementManager.shared
    
    var body: some View {
        if !RevenueCatManager.shared.isSubscribed,
           entitlement.hasVerifiedComplimentaryAccess,
           entitlement.scansRemaining > 0 {
            paywallButton(
                text: "\(entitlement.scansRemaining) complimentary Pro scan\(entitlement.scansRemaining == 1 ? "" : "s") remaining"
            )
        } else if !RevenueCatManager.shared.isSubscribed,
                  entitlement.isComplimentaryExhausted {
            paywallButton(text: "Complimentary Pro scans used — upgrade")
        } else if !RevenueCatManager.shared.isProActive, let score = confidenceScore {
            let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
            if score >= bands.possible && score < bands.strong {
                paywallButton(text: label)
            }
        }
    }

    private func paywallButton(text: String) -> some View {
        Button(action: {
            showPaywall = true
        }) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.footnote.weight(.bold))

                Text(text)
                    .font(.subheadline.weight(.semibold))

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.primary)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
