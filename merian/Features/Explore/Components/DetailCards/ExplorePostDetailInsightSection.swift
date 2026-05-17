import SwiftUI

struct ExplorePostDetailInsightSection: View {
    let scientificName: String
    let currentCommonName: String
    let detail: ExplorePostDetail?
    let isLoading: Bool
    let errorMessage: String?

    private var shouldShowSection: Bool {
        isLoading
            || detail != nil
            || errorMessage != nil
    }

    var body: some View {
        if shouldShowSection {
            VStack(alignment: .leading, spacing: 24) {
                cards

                if let errorMessage, detail == nil {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if isLoading && detail == nil {
            ExploreLoadingInsightCard()
        } else {
            if let detail, detail.hasOverviewContent {
                ExploreOverviewCard(
                    scientificName: scientificName,
                    iucnRedListStatus: detail.iucnRedListStatus,
                    wikipediaOverview: detail.wikipediaOverview
                )
            }

            if let referenceGalleryImages = detail?.referenceGalleryImages,
               !referenceGalleryImages.isEmpty {
                ExploreReferenceGallery(
                    scientificName: scientificName,
                    images: referenceGalleryImages
                )
            }

            if let taxonomyData = detail?.taxonomyData {
                TaxonomyCard(
                    taxonomyData: taxonomyData,
                    scientificName: scientificName
                )
            }

            if let detail, detail.hasHabitatDistributionContent {
                ExploreHabitatDistributionCard(
                    scientificName: scientificName,
                    habitatDescription: detail.habitatDescription,
                    gbifTaxonKey: detail.gbifTaxonKey
                )
            }

            if let similarData = detail?.similarSpeciesData {
                SimilarSpeciesGallery(
                    similarData: similarData,
                    currentScientificName: scientificName,
                    currentCommonName: currentCommonName,
                    routeForSpecies: exploreSimilarSpeciesRoute
                )
            }
        }
    }

    private func exploreSimilarSpeciesRoute(for entry: SimilarSpeciesEntry) -> SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: entry.scientificName,
            speciesId: entry.speciesId,
            entryPoint: .exploreDetailSimilarSpecies
        )
    }
}
