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
        VStack(spacing: 24) {

            InsightHeader(
                title: viewModel.headerTitle,
                subtitle: viewModel.headerSubtitle,
                hazardType: viewModel.hazardType,
                paragraphs: viewModel.headerParagraphs,
                badgeItems: viewModel.headerBadgeItems,
                confidenceScore: inferenceEngine.speciesData?.confidenceScore
            )
            ToxicityBanner()

            // Global Footprint
            ConservationBanner()

            // Diagnostic Evaluation
            if let score = inferenceEngine.speciesData?.confidenceScore, score < MerianConfig.confidenceBands(for: RevenueCatManager.shared.isProActive).diagnosticTrigger, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                DiagnosticComparisonCard(diagnosticData: diagnosticData)
            }

            // Educational Reference
            WikipediaCard(
                isSafariPresented: $isSafariPresented,
                selectedWikiURL: $selectedWikiURL
            )

            // Habitat & Distribution
            if let data = inferenceEngine.speciesData {
                HabitatAndDistributionCard(
                    habitatDescription: data.habitatDescription,
                    scientificName: data.scientificName,
                    scanId: data.scanId
                )
            }

             // Biological Classification
            TaxonomyCard(
                taxonomyData: inferenceEngine.speciesData?.taxonomy,
                scientificName: inferenceEngine.speciesData?.scientificName
            )

            // Spatiotemporal Context
            ScanInformationCard(
                speciesData: inferenceEngine.speciesData,
                timestamp: timestamp
            )
        }
        .padding(.horizontal)
    }
}
