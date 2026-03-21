import SwiftUI
import SafariServices

// MARK: - Layout Subcomponents
extension InsightSheetView {
    
    @ViewBuilder
    var scrollableCanvas: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                InsightCarouselView()
                    .aspectRatio(1.0, contentMode: .fill)
                    .zIndex(0)
                
                VStack(alignment: .leading, spacing: 16) {
                    if let speciesData = inferenceEngine.speciesData, !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                        nonBiologicalContent(for: speciesData)
                    } else {
                        biologicalContent
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 32,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 32
                    )
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                )
                .padding(.top, -32)
                .zIndex(1)
            }
            .frame(width: UIScreen.main.bounds.width)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CommonNameScrollOffsetKey.self,
                        value: geo.frame(in: .scrollView).minY
                    )
                },
                alignment: .top
            )
        }
        .contentMargins(.top, 0, for: .scrollContent)
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
        InsightBiologicalContentView(
            isSafariPresented: $isSafariPresented, 
            selectedWikiURL: $selectedWikiURL,
            timestamp: activeLocalRecord?.timestamp
        )
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
