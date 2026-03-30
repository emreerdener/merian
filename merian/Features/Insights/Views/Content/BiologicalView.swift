import SwiftUI

struct BiologicalView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Bindable var viewModel: InsightSheetViewModel
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?

    // MARK: - Context State
    var timestamp: Date?

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 32) {

            InsightHeader(
                title: viewModel.headerTitle,
                subtitle: viewModel.headerSubtitle,
                hazardType: viewModel.hazardType,
                paragraphs: viewModel.headerParagraphs,
                confidenceScore: inferenceEngine.speciesData?.confidenceScore,
                inferenceTier: inferenceEngine.speciesData?.inferenceTier
            )
            .cardEntrance(index: 0)

            // MARK: - Toxicity Banner
            ToxicityBanner()
                .cardEntrance(index: 1)

            // MARK: - Global Footprint
            ConservationBanner()
                .cardEntrance(index: 2)

            // MARK: - Similar Species Gallery
            /*
            if let similarData = inferenceEngine.speciesData?.similarSpecies {
                // Determine if this qualifies as a low-confidence scan
                let score = inferenceEngine.speciesData?.confidenceScore ?? 1.0
                let threshold = MerianConfig.confidenceBands(forInferenceTier: inferenceEngine.speciesData?.inferenceTier).diagnosticTrigger

                SimilarSpeciesGallery(
                    similarData: similarData,
                    isLowConfidence: score < threshold
                )
            } else if inferenceEngine.isEnrichmentLoading {
                SimilarSpeciesGallery.Skeleton()
            }
            */

            // MARK: - Educational Reference
            OverviewCard(
                isSafariPresented: $isSafariPresented,
                selectedWikiURL: $selectedWikiURL
            )
            .cardEntrance(index: 3)

            // MARK: - Habitat & Distribution
            if let data = inferenceEngine.speciesData {
                HabitatAndDistributionCard(
                    habitatDescription: data.habitatDescription,
                    scientificName: data.scientificName,
                    scanId: data.scanId
                )
                .padding(.top, 8)
                .cardEntrance(index: 4)
            }

            // MARK: - Biological Classification
            TaxonomyCard(
                taxonomyData: inferenceEngine.speciesData?.taxonomy,
                scientificName: inferenceEngine.speciesData?.scientificName
            )
            .cardEntrance(index: 5)

            // MARK: - Spatiotemporal Context
            ScanInformationCard(
                speciesData: inferenceEngine.speciesData,
                timestamp: timestamp
            )
            .cardEntrance(index: 6)

            // MARK: - Custom Tags
            if let scanId = inferenceEngine.speciesData?.scanId {
                UserTagsCard(scanId: scanId)
                    .cardEntrance(index: 7)
            }
        }
        .padding(.horizontal)
    }
}
