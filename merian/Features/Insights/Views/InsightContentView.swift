import SwiftUI

struct InsightContentView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) var modelContext

    @Bindable var viewModel: InsightSheetViewModel
    
    // MARK: - Layout Constants
    private let overlapRadius: CGFloat = 32
    private let imageSize: CGFloat = UIScreen.main.bounds.width
    
    // MARK: - View
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                
                // 1. DYNAMIC STRETCHY CAROUSEL HEADER
                // Embeds firmly inside the native ScrollView to bypass NavigationStack safe area clipping perfectly.
                GeometryReader { proxy in
                    let scrollY = proxy.frame(in: .named("InsightScrollSpace")).minY
                    
                    ImagesCarousel()
                        .frame(width: imageSize, height: scrollY > 0 ? imageSize + scrollY : imageSize)
                        .offset(y: scrollY > 0 ? -scrollY : 0)
                        .ignoresSafeArea(.all, edges: .top) // CRUESCIAL: Kills the 16pt sheet native dragging padding!
                }
                .frame(height: imageSize)
                .ignoresSafeArea(.all, edges: .top) // Ensure the entire geometry wrapper bypasses top safe area
                .zIndex(0)
                
                // 2. OVERLAPPING BOTTOM SHEET CONTENT
                contentCards
                    .padding(.top, overlapRadius)
                    .frame(maxWidth: .infinity)
                    .background(contentSheetBackground)
                    .offset(y: -overlapRadius)
                    .padding(.bottom, -overlapRadius)
                    .zIndex(1)
            }
            .frame(width: imageSize) // CLAMP: Physically guarantees the content bounds can never expand left/right even if child views attempt to breach safe area X bounds.
            .background(scrollOffsetTracker, alignment: .top)
        }
        .coordinateSpace(name: "InsightScrollSpace")
        // Forces native underlap of the translucent NavigationBar completely!
        .ignoresSafeArea(.container, edges: .top)
        .textSelection(.enabled)
        
        // Modal Routings
        .sheet(isPresented: $viewModel.isSafariPresented) {
            if let safeUrl = viewModel.selectedWikiURL {
                SafariView(url: safeUrl)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $viewModel.isFlagIssuePresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                ReportInsightView(scanId: scanId)
            }
        }
    }
}

// MARK: - Subcomponents
private extension InsightContentView {
    
    /// The conditional routing layout parsing Insight structural parameters dynamically.
    @ViewBuilder
    var contentCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            if let speciesData = inferenceEngine.speciesData, 
               !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                
                NonBiologicalView(
                    species: speciesData, 
                    commonName: speciesData.commonName.capitalized
                )
            } else {
                
                BiologicalView(
                    isSafariPresented: $viewModel.isSafariPresented, 
                    selectedWikiURL: $viewModel.selectedWikiURL,
                    timestamp: viewModel.activeLocalRecord?.timestamp
                )
            }
            Spacer(minLength: 40)
        }
    }
    
    /// The rounded white background encapsulating the structural content cards smoothly.
    @ViewBuilder
    var contentSheetBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: overlapRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: overlapRadius
        )
        .fill(Color(uiColor: .systemBackground))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
    }
    
    /// Silent transparent Geometry tracker routing scroll physics mathematically to the Navigation Bar offset.
    @ViewBuilder
    var scrollOffsetTracker: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: CommonNameScrollOffsetKey.self,
                value: geo.frame(in: .scrollView).minY
            )
        }
    }
}
