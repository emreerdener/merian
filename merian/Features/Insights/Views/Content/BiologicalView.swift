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

            // MARK: - Header
            InsightHeader(
                title: viewModel.headerTitle,
                subtitle: viewModel.headerSubtitle,
                hazardType: viewModel.hazardType,
                paragraphs: viewModel.headerParagraphs,
                confidenceScore: inferenceEngine.speciesData?.confidenceScore,
                inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                userIdentificationOverride: inferenceEngine.speciesData?.userIdentificationOverride,
                userConfirmedIdentification: inferenceEngine.speciesData?.userConfirmedIdentification ?? false,
                isFlagged: inferenceEngine.speciesData?.isFlagged ?? false,
                aiScientificName: inferenceEngine.speciesData?.aiScientificName,
                onScrollOffsetChange: { maxY in
                    viewModel.evaluateScrollOffset(minY: maxY)
                }
            )
            .cardEntrance(index: 0)

            // MARK: - Layout Guards
            let isErrorState = inferenceEngine.speciesData?.scientificName == "Offline Mode" ||
                               inferenceEngine.speciesData?.scientificName == "Data Unreadable"
            let isBiological = inferenceEngine.speciesData?.isBiological ?? false

            if !isErrorState && isBiological {
                // MARK: - Identification Candidates
                let hasReviewState = inferenceEngine.speciesData?.userIdentificationOverride != nil ||
                                     inferenceEngine.speciesData?.userConfirmedIdentification == true ||
                                     inferenceEngine.speciesData?.isFlagged == true ||
                                     inferenceEngine.speciesData?.alternativesExhausted == true
                let candidates = inferenceEngine.speciesData?.candidates ?? []
                let confidenceBands = MerianConfig.confidenceBands(forInferenceTier: inferenceEngine.speciesData?.inferenceTier)
                let hasLowConfidence = (inferenceEngine.speciesData?.confidenceScore ?? 1.0) < confidenceBands.diagnosticTrigger
                let isUnknownSubject = inferenceEngine.speciesData?.scientificName == "Taxonomy Unavailable"

                if let primaryAIName = inferenceEngine.speciesData?.aiScientificName,
                   !isUnknownSubject && !hasReviewState && (candidates.count >= 2 || hasLowConfidence) {
                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: primaryAIName,
                        inferenceTier: inferenceEngine.speciesData?.inferenceTier,
                        onFlagIssue: { viewModel.isIdentificationFlagPresented = true },
                        onMatchConfirmed: { viewModel.toastMessage = "Match confirmed" }
                    )
                    .cardEntrance(index: 3)
                }
    
                // MARK: - Toxicity Banner
                ToxicityBanner()
                    .cardEntrance(index: 1)
    
                // MARK: - Educational Reference
                OverviewCard(
                    isSafariPresented: $isSafariPresented,
                    selectedWikiURL: $selectedWikiURL
                )
                .cardEntrance(index: 5)
    
                // MARK: - Habitat & Distribution
                if let data = inferenceEngine.speciesData {
                    HabitatAndDistributionCard(
                        habitatDescription: data.habitatDescription,
                        scientificName: data.scientificName,
                        scanId: data.scanId
                    )
                    .cardEntrance(index: 6)
                }
    
                // MARK: - Biological Classification
                TaxonomyCard(
                    taxonomyData: inferenceEngine.speciesData?.taxonomy,
                    scientificName: inferenceEngine.speciesData?.scientificName
                )
                .cardEntrance(index: 7)
    
                 // MARK: - Similar Species Gallery
                Group {
                    if let similarData = inferenceEngine.speciesData?.similarSpecies {
                        SimilarSpeciesGallery(
                            similarData: similarData
                        )
                        .transition(.opacity)
                    } else if inferenceEngine.isLookalikesLoading {
                        SimilarSpeciesGallery.Skeleton()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: inferenceEngine.isLookalikesLoading)
                .cardEntrance(index: 4)
    
                // MARK: - Spatiotemporal Context
                ScanInformationCard(
                    speciesData: inferenceEngine.speciesData,
                    timestamp: timestamp
                )
                .cardEntrance(index: 8)
    
                // MARK: - Custom Tags
                if let scanId = inferenceEngine.speciesData?.scanId {
                    UserTagsCard(scanId: scanId)
                        .cardEntrance(index: 9)
                }
            }
        }
        .padding(.horizontal)
    }
}
