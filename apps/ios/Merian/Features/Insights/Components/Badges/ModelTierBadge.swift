import SwiftUI

struct ModelTierBadge: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    var label: String = "Upgrade for advanced analysis"
    
    @State private var showPaywall: Bool = false
    
    var body: some View {
        let trialDays = RevenueCatManager.shared.trialDaysRemaining ?? 0
        let isTrialActive = trialDays > 0 && !RevenueCatManager.shared.isSubscribed
        
        if isTrialActive {
            paywallButton(text: "\(trialDays) days of pro remaining")
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
