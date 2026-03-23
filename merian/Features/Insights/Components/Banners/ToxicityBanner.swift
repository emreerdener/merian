import SwiftUI

struct ToxicityBanner: View {
    @Environment(InferenceEngine.self) var inferenceEngine
    
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    var body: some View {
        if isPoisonous {
            HStack {
                Image(systemName: "exclamationmark.circle")
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("Toxic")
                        .font(.system(.headline))
                    Text("This subject could be poisonous.")
                        .font(.system(.subheadline))
                }
                Spacer()
            }
            .padding()
            .background(Color.yellow.opacity(0.8))
            .foregroundColor(.black)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
            )
            // Accessibility: Explicitly anchor screen readers to the threat first
            .accessibilityAddTraits(.isHeader)
        }
    }
}
