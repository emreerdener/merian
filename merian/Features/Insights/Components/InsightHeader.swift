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
    var onScrollOffsetChange: ((CGFloat) -> Void)?
    /// Alternative English common names for this species, excluding the current headline.
    var alternativeCommonNames: [String]? = nil
    /// Called when the user taps the alternative names line to open the name picker.
    var onAlternativeNamesTap: (() -> Void)? = nil

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
                
                // MARK: - Scientific Name
                if !subtitle.isEmpty && subtitle.lowercased() != title.lowercased() {
                    Text(subtitle.strippingCultivarNotation().replacingOccurrences(of: "\n", with: " "))
                        .font(.system(.title3))
                        .italic()
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // MARK: - Common Name
                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(hazardType != "none" ? [] : .isHeader)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .named("InsightScrollSpace")).maxY, initial: true) { _, newMaxY in
                                    onScrollOffsetChange?(newMaxY)
                                }
                        }
                    )

                // MARK: - Alternative Names
                if let alternatives = alternativeCommonNames, !alternatives.isEmpty {
                    let preview = alternatives.prefix(3).joined(separator: " · ")
                    Button(action: { onAlternativeNamesTap?() }) {
                        HStack(spacing: 4) {
                            Text("Also known as: ")
                                .foregroundStyle(.tertiary)
                            + Text(preview)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(.footnote))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Also known as \(preview). Tap to choose preferred name.")
                    .disabled(onAlternativeNamesTap == nil)
                }

                // MARK: - Description
                if !paragraphs.isEmpty {
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
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Haptic punch on reveal
            HapticManager.shared.triggerLightImpact(intensity: 0.5)
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

// MARK: - Scientific Name Display Helpers

private extension String {
    /// Strips cultivar notation for display purposes.
    ///
    /// Per ICNCP, cultivar epithets are enclosed in single quotes (e.g. `Rosa 'Radrazz'`).
    /// This is technically correct but looks unusual to general users. The underlying stored
    /// value is unchanged — this is display-only so DB lookups remain exact-match compatible.
    ///
    /// Handles:
    /// - `Rosa 'Radrazz'`  → `Rosa Radrazz`
    /// - `Malus 'Fuji'`    → `Malus Fuji`
    /// - `Rosa canina`     → `Rosa canina` (unchanged)
    func strippingCultivarNotation() -> String {
        replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
