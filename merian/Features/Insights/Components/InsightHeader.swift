import SwiftUI

struct InsightHeader: View {
    let title: String
    let subtitle: String
    let hazardType: String
    let paragraphs: [String]
    let confidenceScore: Double?

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
             VStack(spacing: 16) {
                 ModelTierBanner(confidenceScore: confidenceScore)
                 ConfidenceBadge(confidenceScore: confidenceScore)
             }
             
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
                            Color.clear.preference(
                                key: CommonNameScrollOffsetKey.self,
                                value: geo.frame(in: .named("InsightScrollSpace")).maxY
                            )
                        }
                    )

                if !paragraphs.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(paragraphs, id: \.self) { paragraph in
                            Text(paragraph)
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
    }
}

// MARK: - Layout Preference Keys
struct CommonNameScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next != .infinity {
            value = next
        }
    }
}
