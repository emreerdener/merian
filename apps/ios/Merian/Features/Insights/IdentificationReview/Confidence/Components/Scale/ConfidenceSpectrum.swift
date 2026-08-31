import SwiftUI

struct ConfidenceSpectrum: View {
    let inferenceTier: String?

    // Derived from MerianConfig so the displayed percentages always match the live thresholds.
    private var bands: MerianConfig.ConfidenceBands { MerianConfig.confidenceBands(forInferenceTier: inferenceTier) }
    private var strongPct: Int { Int(bands.strong * 100) }
    private var possiblePct: Int { Int(bands.possible * 100) }

    var body: some View {
        VStack(spacing: 0) {
            ModelInfoSection(inferenceTier: inferenceTier)
                .padding(.bottom, 24)

            SpectrumNode(
                color: .green,
                nextColor: .orange,
                percentage: "\(strongPct)% – 100%",
                title: "Strong match",
                description: "Extremely certain. The key morphological traits match the model flawlessly."
            )

            SpectrumNode(
                color: .orange,
                nextColor: .gray,
                percentage: "\(possiblePct)% – \(strongPct - 1)%",
                title: "Possible match",
                description: "A likely match, but key identifying traits may be obscured, blurry, or missing."
            )

            SpectrumNode(
                color: .gray,
                nextColor: nil,
                percentage: "Below \(possiblePct)%",
                title: "Weak match",
                description: "The model is uncertain. Try capturing another angle or bringing it into focus."
            )
            
            AIMistakesBanner()
                .padding(.top, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, 16)
    }
}

private struct AIMistakesBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)
                
                Text("AI can make mistakes")
                    .font(.callout.bold())
                    .foregroundColor(.primary)
            }
            
            Text("While Naturebook uses advanced models, consider verifying critical identifications with experts, especially regarding toxicity or foraging.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.yellow.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
