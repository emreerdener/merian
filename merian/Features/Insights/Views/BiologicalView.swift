import SwiftUI

struct BiologicalView: View {
    // MARK: - Dependencies
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    // MARK: - Context State
    var timestamp: Date? = nil

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 8) {
            
            // 1. Primary Identifiers
            InsightHeader(speciesData: inferenceEngine.speciesData)
            ToxicityBanner()
            
            // 2. Biological Classification
            TaxonomyCard(
                taxonomyData: inferenceEngine.speciesData?.taxonomy,
                scientificName: inferenceEngine.speciesData?.scientificName
            )
            
            // 3. Spatiotemporal Context
            ScanInformationCard(
                speciesData: inferenceEngine.speciesData, 
                timestamp: timestamp
            )

            // 4. Global Footprint
            ConservationBanner()
                
            // 5. Educational Reference
            WikipediaCard(
                isSafariPresented: $isSafariPresented, 
                selectedWikiURL: $selectedWikiURL
            )
            
            // 6. Diagnostic Evaluation
            if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.8, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                AIReasoningCard(diagnosticData: diagnosticData)
            }
        }
        .padding(.horizontal)
    }
}


