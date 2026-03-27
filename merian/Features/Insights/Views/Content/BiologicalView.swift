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
            
            // Educational Reference
            WikipediaCard(
                isSafariPresented: $isSafariPresented, 
                selectedWikiURL: $selectedWikiURL
            )

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
            
            // Global Occurrence Heatmap — available to all users when GBIF key is present
            if let key = inferenceEngine.speciesData?.gbifTaxonKey {
                GBIFHeatmapMapView(taxonKey: key)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            // Habitat & Distribution
            if let data = inferenceEngine.speciesData {
                SpeciesInsightsCard(
                    habitatDescription: data.habitatDescription,
                    globalDistributionRegions: data.globalDistributionRegions,
                    scientificName: data.scientificName,
                    scanId: data.scanId
                )
            }
            
            // Diagnostic Evaluation
            if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.8, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                DiagnosticComparisonCard(diagnosticData: diagnosticData)
            }
        }
        .padding(.horizontal)
    }
}
