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
                    Text("DANGER: TOXIC")
                        .font(.headline)
                    Text("This subject is known to be poisonous.")
                        .font(.subheadline)
                }
                Spacer()
                
                Button(action: {
                    print("Contact Local Experts Triggered")
                }) {
                    Text("Contact")
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                // Accessibility: Clear interactive routing
                .accessibilityHint("Double tap to contact local poison control experts.")
            }
            .padding()
            .background(Color.red.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(12)
            // Accessibility: Explicitly anchor screen readers to the threat first
            .accessibilityAddTraits(.isHeader)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.gray)
                    .padding(.top, 2)
                Text("Edibility Unknown. Merian is an educational tool. Never ingest wild flora.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}
