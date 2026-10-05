import SwiftUI

struct InsightHeader: View {
    let title: String
    let subtitle: String
    let hazardType: String
    let paragraphs: [String]
    let confidenceScore: Double?
    let inferenceTier: String?
    var provenance: IdentificationResultProvenance?
    var primaryRankDescription: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?
    var onAskCommunity: (() -> Void)?
    var prepareSavedReanalysis: SavedReanalysisPreparation?
    var onScrollOffsetChange: ((CGFloat) -> Void)?
    /// Alternative English common names for this species, excluding the current headline.
    var alternativeCommonNames: [String]?
    /// Called when the user taps the alternative names line to open the name picker.
    var onAlternativeNamesTap: (() -> Void)?
    var onRevealFeedback: () -> Void = {}
    var modelTierBadgePresentation: ModelTierBadgePresentation?
    var onModelTierUpgrade: () -> Void = {}

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            ConfidenceBadge(
                    confidenceScore: confidenceScore,
                    inferenceTier: inferenceTier,
                    provenance: provenance,
                    userIdentificationOverride: userIdentificationOverride,
                    userConfirmedIdentification: userConfirmedIdentification,
                    isFlagged: isFlagged,
                    aiScientificName: aiScientificName,
                    onAskCommunity: onAskCommunity,
                    prepareSavedReanalysis: prepareSavedReanalysis
                )

            if let primaryRankDescription {
                Text(primaryRankDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // MARK: - Subtitle and Title
            VStack(alignment: .center, spacing: 8) {

                // MARK: - Scientific Name
                if !subtitle.isEmpty && subtitle.lowercased() != title.lowercased() && subtitle != "Taxonomy Unavailable" {
                    Text(subtitle.strippingCultivarNotation().replacingOccurrences(of: "\n", with: " "))
                        .font(.system(.title3))
                        .italic()
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // MARK: - Common Name
                let hasPicker = alternativeCommonNames?.isEmpty == false && onAlternativeNamesTap != nil
                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(hazardType != "none" ? [] : .isHeader)
                    .accessibilityHint(hasPicker ? "Tap to choose a preferred name" : "")
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .named("InsightScrollSpace")).maxY, initial: true) { _, newMaxY in
                                    onScrollOffsetChange?(newMaxY)
                                }
                        }
                    )
                    .onTapGesture {
                        if hasPicker { onAlternativeNamesTap?() }
                    }

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
                            analysisParagraph(paragraph)
                                .font(.system(.body))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
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
            onRevealFeedback()
        }

        // MARK: - Model Tier Badge
        ModelTierBadge(
            presentation: modelTierBadgePresentation,
            onUpgrade: onModelTierUpgrade
        )
    }

    @ViewBuilder
    private func analysisParagraph(_ paragraph: String) -> some View {
        let attributed = styledParagraph(text: paragraph, scientificName: subtitle)
        if #available(iOS 18.0, *) {
            roundedHighlightText(attributed)
                .textRenderer(ScientificNameHighlightRenderer())
        } else {
            Text(attributed)
        }
    }

    @available(iOS 18.0, *)
    private func roundedHighlightText(_ attributed: AttributedString) -> Text {
        attributed.runs.reduce(Text(verbatim: "")) { result, run in
            var segment = AttributedString(attributed[run.range])
            let isHighlighted = segment.backgroundColor != nil
            segment.backgroundColor = nil
            let text = Text(segment)
            let styled = isHighlighted ? text.customAttribute(ScientificNameHighlight()) : text
            return Text("\(result)\(styled)")
        }
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

@available(iOS 18.0, *)
private struct ScientificNameHighlight: TextAttribute {}

@available(iOS 18.0, *)
private struct ScientificNameHighlightRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[ScientificNameHighlight.self] != nil {
                    // Each wrapped segment keeps its own subtly rounded background.
                    let background = RoundedRectangle(cornerRadius: 3)
                        .path(in: run.typographicBounds.rect)
                    context.fill(background, with: .color(.secondary.opacity(0.15)))
                }
                context.draw(run)
            }
        }
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
