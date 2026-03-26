import SwiftUI

struct ConfidenceSpectrum: View {
    // Derived from MerianConfig so the displayed percentages always match the live thresholds.
    private static let strongPct  = Int(MerianConfig.confidenceStrongThreshold   * 100)
    private static let possiblePct = Int(MerianConfig.confidencePossibleThreshold * 100)

    var body: some View {
        VStack(spacing: 0) {
            SpectrumNode(
                color: .green,
                nextColor: .orange,
                percentage: "\(Self.strongPct)% – 100%",
                title: "Strong match",
                description: "Extremely certain. The key morphological traits match the model flawlessly."
            )

            SpectrumNode(
                color: .orange,
                nextColor: .gray,
                percentage: "\(Self.possiblePct)% – \(Self.strongPct - 1)%",
                title: "Possible match",
                description: "A likely match, but key identifying traits may be obscured, blurry, or missing."
            )

            SpectrumNode(
                color: .gray,
                nextColor: nil,
                percentage: "Below \(Self.possiblePct)%",
                title: "Weak match",
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
