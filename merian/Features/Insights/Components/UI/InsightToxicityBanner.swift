import SwiftUI

struct InsightToxicityBanner: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    var body: some View {
        if isPoisonous {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("TOXIC")
                        .font(.system(.headline))
                    Text("This subject is known to be poisonous.")
                        .font(.system(.subheadline))
                }
                Spacer()
            }
            .padding()
            .background(Color.red.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
            )
            // Accessibility: Explicitly anchor screen readers to the threat first
            .accessibilityAddTraits(.isHeader)
            .shadow(color: .red.opacity(0.5), radius: 10, y: 5)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 2)
                Text("Merian is an educational tool. Never ingest wild flora. Be cautious around unknown species.")
                    .font(.system(.caption))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                Spacer()
            }
            .glassCard()
        }
    }
}
