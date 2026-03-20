import SwiftUI
import SafariServices

// MARK: - Layout Subcomponents
extension InsightSheetView {
    
    @ViewBuilder
    var scrollableCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InsightCarouselView()
                    .background(GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("SheetScroll")).minY
                        )
                    })
                
                if let speciesData = inferenceEngine.speciesData, !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                    nonBiologicalContent(for: speciesData)
                } else {
                    biologicalContent
                }
                
                Spacer(minLength: 40)
            }
        }
        .coordinateSpace(name: "SheetScroll")
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
        VStack(alignment: .leading, spacing: 16) {
            Text(commonName)
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(species.insightData.description)
                .font(.system(.body, design: .serif))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(6)
        }
        .glassCard()
        .padding(.horizontal)
    }
    
    @ViewBuilder
    var biologicalContent: some View {
        InsightTaxonomyHeader()
            .padding(.horizontal)
        
        InsightToxicityBanner()
            .padding(.horizontal)
            .padding(.top, 8)
            
        InsightTaxonomyTree()
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
        
        InsightConservationCard()
            .padding(.horizontal)
            .padding(.top, 8)
    }
    
    @ViewBuilder
    var celebrationOverlay: some View {
        if showCelebration {
            VStack {
                NewDiscoveryCelebrationView(
                    commonName: commonName,
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showCelebration = false
                        }
                    }
                )
                .padding(.top, 16)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
        }
    }
    
    @ViewBuilder
    var addCollectionButton: some View {
        Menu {
            Button(action: { print("Added to Favorites") }) {
                Label("Favorites", systemImage: "star")
            }
            Button(action: { print("Added to Sightings") }) {
                Label("Sightings", systemImage: "eye")
            }
            Divider()
            Button(action: { showCollectionPicker = true }) {
                Label("New Collection...", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Add to collection")
            }
            .padding(.horizontal, 16)
            .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    var shareActionButton: some View {
        Button(action: { shareDiscovery() }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.borderedProminent)
    }
}
