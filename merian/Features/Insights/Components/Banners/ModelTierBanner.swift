import SwiftUI

struct ModelTierBanner: View {
    let confidenceScore: Double?
    
    var body: some View {
        if !RevenueCatManager.shared.isProActive, let score = confidenceScore {
            let bands = MerianConfig.confidenceBands(for: false)
            if score >= bands.possible && score < bands.strong {
            Button(action: {
                AppEventPublisher.shared.send(.triggerPaywall)
            }) {
                HStack(alignment: .center, spacing: 6) {
                    Text("Get higher confidence with Pro")
                        .font(.footnote.weight(.medium))
                        
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            }
        }
    }
}
