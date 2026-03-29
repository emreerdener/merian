import SwiftUI

struct ModelTierBadge: View {
    let confidenceScore: Double?
    let inferenceTier: String?
    
    var body: some View {
        if !RevenueCatManager.shared.isProActive, let score = confidenceScore {
            let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
            if score >= bands.possible && score < bands.strong {
            Button(action: {
                AppEventPublisher.shared.send(.triggerPaywall)
            }) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.footnote.weight(.bold))
                        
                    Text("Get higher confidence with Pro")
                        .font(.footnote.weight(.medium))
                        
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
            }
        }
    }
}
