import SwiftUI

struct BiologicalView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Bindable var viewModel: InsightSheetViewModel
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?

    // MARK: - Context State
    var timestamp: Date? = nil

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

            // MARK: - Toxicity Banner
            ToxicityBanner()

            // MARK: - Global Footprint
            ConservationBanner()

            // MARK: - Diagnostic Evaluation
            if let score = inferenceEngine.speciesData?.confidenceScore, score < MerianConfig.confidenceBands(forInferenceTier: inferenceEngine.speciesData?.inferenceTier).diagnosticTrigger, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                DiagnosticComparisonCard(diagnosticData: diagnosticData)
            }

            // MARK: - Educational Reference
            OverviewCard(
                isSafariPresented: $isSafariPresented,
                selectedWikiURL: $selectedWikiURL
            )

            // MARK: - Habitat & Distribution
            if let data = inferenceEngine.speciesData {
                HabitatAndDistributionCard(
                    habitatDescription: data.habitatDescription,
                    scientificName: data.scientificName,
                    scanId: data.scanId
                )
                .padding(.top, 8)
            }

            // MARK: - Biological Classification
            TaxonomyCard(
                taxonomyData: inferenceEngine.speciesData?.taxonomy,
                scientificName: inferenceEngine.speciesData?.scientificName
            )

            // MARK: - Spatiotemporal Context
            ScanInformationCard(
                speciesData: inferenceEngine.speciesData,
                timestamp: timestamp
            )
            
            // MARK: - Custom Tags
            if let scanId = inferenceEngine.speciesData?.scanId {
                UserTagsCard(scanId: scanId)
            }
        }
        .padding(.horizontal)
    }
}
