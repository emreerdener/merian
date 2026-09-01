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
                    .gbifHeatmapCardChrome()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    MerianCardHeader(systemImage: "globe", title: "Habitat & distribution")

                    if let trimmedHabitatDescription {
                        Text(
                            ScientificNameStyler.highlightedText(
                                trimmedHabitatDescription,
                                scientificName: scientificName
                            )
                        )
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
}
