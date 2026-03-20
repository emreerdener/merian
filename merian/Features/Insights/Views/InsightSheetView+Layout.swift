import SwiftUI
import SafariServices

// MARK: - Layout Subcomponents
extension InsightSheetView {
    
    @ViewBuilder
    var scrollableCanvas: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                InsightCarouselView()
                
                if let speciesData = inferenceEngine.speciesData, !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                    nonBiologicalContent(for: speciesData)
                } else {
                    biologicalContent
                }
                
                Spacer(minLength: 40)
            }
        }
        .textSelection(.enabled)
        .sheet(isPresented: $isSafariPresented) {
            if let safeUrl = selectedWikiURL {
                SafariView(url: safeUrl)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isFlagIssuePresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                FlagIssueView(scanId: scanId)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
    
    @ViewBuilder
    func nonBiologicalContent(for species: SpeciesData) -> some View {
        InsightNonBiologicalContentView(species: species, commonName: commonName)
    }
    
    @ViewBuilder
    var biologicalContent: some View {
        InsightBiologicalContentView(isSafariPresented: $isSafariPresented, selectedWikiURL: $selectedWikiURL)
    }
    
    @ViewBuilder
    var celebrationOverlay: some View {
        InsightCelebrationOverlayView(
            commonName: commonName,
            showCelebration: $showCelebration
        )
    }
    
    @ViewBuilder
    var addCollectionButton: some View {
        InsightAddCollectionButtonView(
            collections: collections,
            activeLocalRecord: activeLocalRecord,
            toggleScanInCollection: { collection in toggleScanInCollection(collection) },
            showNewCollectionAlert: $showNewCollectionAlert,
            hasScanId: inferenceEngine.speciesData?.scanId != nil
        )
    }
    
    @ViewBuilder
    var shareActionButton: some View {
        InsightShareActionButtonView(
            shareDiscovery: { shareDiscovery() }
        )
    }
}
