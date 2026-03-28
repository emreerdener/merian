import SwiftUI

struct ModelTierBanner: View {
    var body: some View {
        if !RevenueCatManager.shared.isProActive {
            Button(action: {
                AppEventPublisher.shared.send(.triggerPaywall)
            }) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundColor(.purple)
                        .frame(width: 24, alignment: .center)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upgrade to Pro")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        
                        Text("Unlock advanced AI vision models for higher accuracy.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
