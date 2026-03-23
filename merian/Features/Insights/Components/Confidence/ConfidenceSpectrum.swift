import SwiftUI

struct ConfidenceSpectrum: View {
    var body: some View {
        VStack(spacing: 0) {
            SpectrumNode(
                color: Color(red: 0.11, green: 0.52, blue: 0.28),
                nextColor: Color(red: 0.25, green: 0.75, blue: 0.35),
                percentage: "95% - 100%",
                title: "High confidence",
                description: "Extremely certain. The key visual structures match the model flawlessly."
            )
            
            SpectrumNode(
                color: Color(red: 0.25, green: 0.75, blue: 0.35),
                nextColor: .orange,
                percentage: "85% - 94%",
                title: "Confident",
                description: "Highly probable. Traits align perfectly with standard species morphology."
            )
            
            SpectrumNode(
                color: .orange,
                nextColor: .red,
                percentage: "70% - 84%",
                title: "Educated guess",
                description: "A likely match, but key identifying traits may be obscured, blurry, or missing."
            )
            
            SpectrumNode(
                color: .red,
                nextColor: nil,
                percentage: "Below 70%",
                title: "Low confidence",
                description: "The model is uncertain. Try capturing another angle or bringing it into focus."
            )
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill).opacity(0.5)) // Ambient Glass Card Housing
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1) // Structural Glare Line
                )
        )
        .padding(.horizontal, 16)
    }
}
