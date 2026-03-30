import SwiftUI

struct InsightHeader: View {
    let title: String
    let subtitle: String
    let hazardType: String
    let paragraphs: [String]
    let confidenceScore: Double?
    let inferenceTier: String?
    var onScrollOffsetChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            
            ConfidenceBadge(confidenceScore: confidenceScore, inferenceTier: inferenceTier)
             
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
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .named("InsightScrollSpace")).maxY, initial: true) { _, newMaxY in
                                    onScrollOffsetChange?(newMaxY)
                                }
                        }
                    )

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
                    .padding(.top, 8) // Separates the text distinctively from the bold title
                }
             }
        }
        .frame(maxWidth: .infinity)

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
