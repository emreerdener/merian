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
            VStack(alignment: .leading, spacing: 0) {
                GBIFHeatmapMapView(taxonKey: gbifTaxonKey)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.3), lineWidth: 4)
                            .blur(radius: 6)
                            .offset(y: 2)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                        Text("Habitat & distribution")
                            .font(.system(.headline))
                            .foregroundColor(.primary)
                    }

                    if let trimmedHabitatDescription {
                        Text(styledHabitat(text: trimmedHabitatDescription))
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, -16)
        }
    }

    private func styledHabitat(text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !scientificName.isEmpty else { return result }

        var searchRange = result.startIndex..<result.endIndex
        while let range = result[searchRange].range(of: scientificName, options: .caseInsensitive) {
            result[range].font = .system(.body, design: .monospaced)
            result[range].backgroundColor = Color.secondary.opacity(0.15)
            searchRange = range.upperBound..<result.endIndex
        }

        return result
    }
}
