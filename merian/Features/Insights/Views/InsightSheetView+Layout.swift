import SwiftUI
import SafariServices

// MARK: - Layout Subcomponents
extension InsightSheetView {
    
    @ViewBuilder
    var scrollableCanvas: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
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
        InsightNonBiologicalContentView(species: species, commonName: commonName)
    }
    
    @ViewBuilder
    var biologicalContent: some View {
        InsightBiologicalContentView(isSafariPresented: $isSafariPresented, selectedWikiURL: $selectedWikiURL)
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
            if let favorites = collections.first(where: { $0.name == "Favorites" }) {
                let isFavorited = activeLocalRecord?.collections?.contains(where: { $0.id == favorites.id }) ?? false
                Button(action: { toggleScanInCollection(favorites) }) {
                    Label("Favorites", systemImage: isFavorited ? "heart.fill" : "heart")
                }
                Divider()
            }
            
            ForEach(collections.filter { $0.name != "Favorites" }) { collection in
                let isSelected = activeLocalRecord?.collections?.contains(where: { $0.id == collection.id }) ?? false
                Button(action: { toggleScanInCollection(collection) }) {
                    Label(collection.name, systemImage: isSelected ? "checkmark.circle.fill" : "folder")
                }
            }
            Divider()
            Button(action: { showNewCollectionAlert = true }) {
                Label("New Collection...", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 6) {
                Text("Add to collection")
            }
            .padding(.horizontal, 16)
            .foregroundColor(.secondary)
        }
        .disabled(inferenceEngine.speciesData?.scanId == nil)
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
