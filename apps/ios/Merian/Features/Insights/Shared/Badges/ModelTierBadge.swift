import SwiftUI

struct ModelTierBadge: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    var label: String = "Upgrade for advanced analysis"
    var complimentaryDisplayOverride: ComplimentaryScanDisplayState?
    
    @State private var showPaywall: Bool = false
    @State private var entitlement = EntitlementManager.shared

    private var isSubscribed: Bool {
        complimentaryDisplayOverride == nil && RevenueCatManager.shared.isSubscribed
    }

    private var isProActive: Bool {
        complimentaryDisplayOverride?.hasAccess ?? RevenueCatManager.shared.isProActive
    }

    private var hasComplimentaryAccess: Bool {
        complimentaryDisplayOverride?.hasAccess ?? entitlement.hasVerifiedComplimentaryAccess
    }

    private var scansRemaining: Int {
        complimentaryDisplayOverride?.scansRemaining ?? entitlement.scansRemaining
    }

    private var isComplimentaryExhausted: Bool {
        complimentaryDisplayOverride?.isExhausted ?? entitlement.isComplimentaryExhausted
    }
    
    var body: some View {
        if !isSubscribed,
           hasComplimentaryAccess,
           scansRemaining > 0 {
            paywallButton(
                text: "\(scansRemaining) complimentary Pro scan\(scansRemaining == 1 ? "" : "s") remaining"
            )
        } else if !isSubscribed,
                  isComplimentaryExhausted {
            paywallButton(text: "Complimentary Pro scans used — upgrade")
        } else if !isProActive, let score = confidenceScore {
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
