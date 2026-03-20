import SwiftUI

struct InsightBiologicalContentView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?

    var body: some View {
        InsightTaxonomyHeader(speciesData: inferenceEngine.speciesData)
            .padding(.horizontal)
        
        InsightToxicityBanner()
            .padding(.horizontal)
            .padding(.top, 8)
            
        InsightTaxonomyTree(
            taxonomyData: inferenceEngine.speciesData?.taxonomy,
            scientificName: inferenceEngine.speciesData?.scientificName
        )
            .padding(.horizontal)
            .padding(.top, 8)

        InsightConservationCard()
            .padding(.horizontal)
            .padding(.top, 8)
            
        InsightDescriptionSection(isSafariPresented: $isSafariPresented, selectedWikiURL: $selectedWikiURL)
            .padding(.horizontal)
            .padding(.top, 8)
        
        if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.8, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
            DiagnosticComparisonView(diagnosticData: diagnosticData)
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }
}
