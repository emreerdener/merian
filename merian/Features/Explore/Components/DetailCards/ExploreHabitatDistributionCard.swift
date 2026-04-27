import SwiftUI

struct ExploreHabitatDistributionCard: View {
    let scientificName: String
    let habitatDescription: String?
    let gbifTaxonKey: Int?

    private var trimmedHabitatDescription: String? {
        guard let habitatDescription else { return nil }
        let trimmed = habitatDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        if gbifTaxonKey != nil || trimmedHabitatDescription != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text("Habitat & distribution")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                if let gbifTaxonKey {
                    GBIFHeatmapMapView(taxonKey: gbifTaxonKey)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }

                if let trimmedHabitatDescription {
                    Text(styledHabitat(text: trimmedHabitatDescription))
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private func styledHabitat(text: String) -> AttributedString {
        var result = AttributedString(text)
        var searchRange = result.startIndex..<result.endIndex

        while let range = result[searchRange].range(of: scientificName, options: .caseInsensitive) {
            result[range].font = .system(.body, design: .monospaced)
            result[range].backgroundColor = Color.secondary.opacity(0.15)
            searchRange = range.upperBound..<result.endIndex
        }

        return result
    }
}
