import SwiftUI

struct InsightHeader: View {
    let speciesData: SpeciesData?
    
    private var commonName: String {
        speciesData?.commonName.capitalized ?? "Scanning Subject..."
    }
    private var scientificName: String {
        speciesData?.scientificName ?? "Awaiting Taxonomy"
    }
    private var isPoisonous: Bool {
        speciesData?.insightData.isPoisonous ?? false
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 24) {
             VStack(alignment: .center, spacing: 8) {
                Text(scientificName)
                    .font(.system(.title3))
                    .italic()
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            
                Text(commonName)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(isPoisonous ? [] : .isHeader)

                // Description tightly coupled with semantic taxonomy traits
                if let species = speciesData, !species.insightData.description.isEmpty {
                    let paragraphs = species.insightData.description
                        .components(separatedBy: .newlines)
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    
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

            if let species = speciesData {
                // Species Badges geometrically decoupled
                SpeciesBadges(species: species)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Center Wrapping Flow Layout
struct CenterFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? UIScreen.main.bounds.width
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                height += lineHeight + spacing
                currentX = size.width + spacing
                lineHeight = size.height
            } else {
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        height += lineHeight
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var lines: [[(Int, CGSize)]] = []
        var currentLine: [(Int, CGSize)] = []
        var currentX: CGFloat = 0
        
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.width && !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = []
                currentX = 0
            }
            currentLine.append((index, size))
            currentX += size.width + spacing
        }
        if !currentLine.isEmpty { lines.append(currentLine) }
        
        var y = bounds.minY
        for line in lines {
            let lineWidth = line.map { $0.1.width }.reduce(0, +) + CGFloat(line.count - 1) * spacing
            var x = bounds.minX + (bounds.width - lineWidth) / 2
            let lineHeight = line.map { $0.1.height }.max() ?? 0
            
            for (index, size) in line {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += lineHeight + spacing
        }
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
