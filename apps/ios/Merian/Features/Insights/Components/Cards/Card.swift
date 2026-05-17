import SwiftUI

// MARK: - Global Liquid Glass Aesthetic Modifier
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
    }
}

extension View {
    func card() -> some View {
        self.modifier(CardModifier())
    }
}

// MARK: - Shared Insight/Explore Card Chrome

struct InsightCardHeader<Accessory: View>: View {
    let systemImage: String
    let title: String
    let accessory: Accessory

    init(
        systemImage: String,
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(.headline))
                .foregroundColor(.primary)
            accessory
        }
    }
}

extension InsightCardHeader where Accessory == EmptyView {
    init(systemImage: String, title: String) {
        self.init(systemImage: systemImage, title: title) {
            EmptyView()
        }
    }
}

struct WikipediaSummarySection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WIKIPEDIA")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(.body))
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WikipediaReadMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Read more on Wikipedia")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .foregroundColor(.blue)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

enum InsightScientificNameStyler {
    static func highlightedText(_ text: String, scientificName: String?) -> AttributedString {
        var result = AttributedString(text)
        guard let scientificName, !scientificName.isEmpty else { return result }

        var searchRange = result.startIndex..<result.endIndex
        while let range = result[searchRange].range(of: scientificName, options: .caseInsensitive) {
            result[range].font = .system(.body, design: .monospaced)
            result[range].backgroundColor = Color.secondary.opacity(0.15)
            searchRange = range.upperBound..<result.endIndex
        }

        return result
    }
}

private struct GBIFHeatmapCardChromeModifier: ViewModifier {
    private let cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.3), lineWidth: 4)
                    .blur(radius: 6)
                    .offset(y: 2)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    func gbifHeatmapCardChrome() -> some View {
        modifier(GBIFHeatmapCardChromeModifier())
    }
}
