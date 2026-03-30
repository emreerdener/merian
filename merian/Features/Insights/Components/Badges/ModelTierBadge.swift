import SwiftUI

struct ModelTierBadge: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    
    @State private var showPaywall: Bool = false
    
    var body: some View {
        if !RevenueCatManager.shared.isProActive, let score = confidenceScore {
            let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
            if score >= bands.possible && score < bands.strong {
            Button(action: {
                showPaywall = true
            }) {
                HStack(alignment: .center, spacing: 8) {
                     Image(systemName: "sparkle")
                        .font(.footnote.weight(.bold))

                    Text("Upgrade for advanced analysis")
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
    }
}
