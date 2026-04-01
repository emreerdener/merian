import SwiftUI

struct InsightHeader: View {
    let title: String
    let subtitle: String
    let hazardType: String
    let paragraphs: [String]
    let confidenceScore: Double?
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?
    /// Vision streaming text captured at the moment Gemini responded.
    /// When set, the paragraph slot shows this text first then cross-fades to
    /// `paragraphs` (Gemini aiReasoning) and the title entrance is animated.
    var visionTransitionText: String?
    var onScrollOffsetChange: ((CGFloat) -> Void)?

    @State private var titleVisible: Bool = false
    @State private var showVisionParagraph: Bool = true

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            ConfidenceBadge(
                    confidenceScore: confidenceScore,
                    inferenceTier: inferenceTier,
                    userIdentificationOverride: userIdentificationOverride,
                    userConfirmedIdentification: userConfirmedIdentification,
                    isFlagged: isFlagged,
                    aiScientificName: aiScientificName
                )

            // MARK: - Subtitle and Title
            VStack(alignment: .center, spacing: 8) {
                Text(subtitle)
                    .font(.system(.title3))
                    .italic()
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(hazardType != "none" ? [] : .isHeader)
                    // Entrance animation only when arriving from analyzing state
                    .opacity(visionTransitionText != nil ? (titleVisible ? 1 : 0) : 1)
                    .offset(y: visionTransitionText != nil ? (titleVisible ? 0 : 10) : 0)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .named("InsightScrollSpace")).maxY, initial: true) { _, newMaxY in
                                    onScrollOffsetChange?(newMaxY)
                                }
                        }
                    )

                // MARK: - Description
                // Shows Vision streaming text first, then cross-fades to Gemini aiReasoning
                if let visionText = visionTransitionText, showVisionParagraph {
                    Text(visionText)
                        .font(.system(.body))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 8)
                        .transition(.opacity)
                } else if !paragraphs.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(paragraphs, id: \.self) { paragraph in
                            Text(styledParagraph(text: paragraph, scientificName: subtitle))
                                .font(.system(.body))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                }
             }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.45), value: showVisionParagraph)
        .onAppear {
            guard visionTransitionText != nil else { return }
            // Haptic punch on the reveal moment — fires with the title entrance
            HapticManager.shared.triggerLightImpact(intensity: 0.5)
            // Animate title in after a brief settle delay
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.15)) {
                titleVisible = true
            }
            // Cross-fade paragraph from Vision text to Gemini aiReasoning
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                HapticManager.shared.triggerSelectionPulse()
                showVisionParagraph = false
            }
        }

        // MARK: - Model Tier Badge
        ModelTierBadge(confidenceScore: confidenceScore, inferenceTier: inferenceTier)
    }

    private func styledParagraph(text: String, scientificName: String) -> AttributedString {
        let cleanText = text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "_", with: "")
        var result = AttributedString(cleanText)
        
        if !scientificName.isEmpty {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: scientificName, options: .caseInsensitive) {
                result[range].font = .system(.body, design: .monospaced)
                result[range].backgroundColor = Color.secondary.opacity(0.15)
                searchRange = range.upperBound..<result.endIndex
            }
        }
        
        return result
    }
}
