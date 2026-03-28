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

            // MARK: - Toxicity Banner
            ToxicityBanner()

            // MARK: - Global Footprint
            ConservationBanner()

            // MARK: - Diagnostic Evaluation
            if let score = inferenceEngine.speciesData?.confidenceScore, score < MerianConfig.confidenceBands(for: RevenueCatManager.shared.isProActive).diagnosticTrigger, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                DiagnosticComparisonCard(diagnosticData: diagnosticData)
            }

            // MARK: - Educational Reference
            WikipediaCard()

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

            // MARK: - External Links
            if let wikiString = inferenceEngine.speciesData?.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                Button(action: {
                    selectedWikiURL = wikiUrl
                    isSafariPresented = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text("Learn more on Wikipedia")
                            .font(.headline)
                    }
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
        .padding(.horizontal)
    }
}
