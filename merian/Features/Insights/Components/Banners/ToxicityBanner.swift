import SwiftUI

struct ToxicityBanner: View {
    @Environment(InferenceEngine.self) var inferenceEngine
    
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
        }
    }
}
