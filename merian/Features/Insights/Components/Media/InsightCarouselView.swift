import SwiftUI

struct InsightCarouselView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @State private var selectedIndex: Int = 0
    
    // MARK: - Computed State Data Loaders
    private var refUrls: [String] {
        inferenceEngine.speciesData?.referenceImageUrl?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
    private var validHistoricImagePaths: [String] {
        inferenceEngine.validHistoricImagePaths
    }
    private var hasLive: Bool {
        inferenceEngine.activeImageData != nil
    }
    private var liveCount: Int {
        hasLive ? 1 : 0
    }
    private var totalImages: Int {
        liveCount + validHistoricImagePaths.count + refUrls.count
    }
    
    // MARK: - Body
    var body: some View {
        if totalImages > 0 {
            VStack(spacing: 0) {
                imageTabs
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .id("InsightCarousel_\(totalImages)_\(inferenceEngine.speciesData?.scanId ?? "null")")
                    .aspectRatio(1.0, contentMode: .fill)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),   // Anchor opaque at top
                                .init(color: .black, location: 0.7),   // Hold fully opaque down to exactly 80%
                                .init(color: .clear, location: 1.0)    // Rapidly fade to clear only in the final 20%
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipped() // Ensure the image layer natively truncates inside its own view logic alone
                    .overlay(alignment: .bottom) { paginationDots }
                    .overlay(alignment: .top) {
                        ZStack(alignment: .top) {
                            // Layer 1: Protective Semantic Top Gradient
                            LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 120)
                                .allowsHitTesting(false)
                                .zIndex(0)
                            
                            // Layer 2: Highest-Index Confidence Badge
                            ConfidenceBadgeView(confidenceScore: inferenceEngine.speciesData?.confidenceScore)
                                .padding(.top, 24)
                                .zIndex(100) // Mathematically forces it completely outside the gradient render layer
                        }
                    }
            }
        }
    }
}

// MARK: - Subcomponents
private extension InsightCarouselView {
    
    @ViewBuilder
    var imageTabs: some View {
        TabView(selection: $selectedIndex) {
            // Priority: Live Capture actively evaluated (Data payload)
            if hasLive, let livePayload = inferenceEngine.activeImageData, let uiImage = UIImage(data: livePayload) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1.0, contentMode: .fill)
                    .clipped()
                    .tag(0)
            }
            
            // User's Uploaded Images
            ForEach(Array(validHistoricImagePaths.enumerated()), id: \.offset) { index, path in
                AsyncLocalImageView(
                    imagePath: path,
                    onImageLoadFailed: {
                        if totalImages > 1 {
                            inferenceEngine.dropInvalidCarouselImage(path)
                            if selectedIndex >= totalImages - 1 {
                                selectedIndex = max(0, totalImages - 2)
                            }
                        }
                    }
                )
                .tag(liveCount + index)
            }
            
            // Tab 1+: Wikipedia / GBIF Reference Images
            ForEach(Array(refUrls.enumerated()), id: \.offset) { index, urlString in
                if let refUrl = URL(string: urlString) {
                    AsyncImage(url: refUrl, transaction: Transaction(animation: .easeInOut(duration: 0.3))) { phase in
                        switch phase {
                        case .empty:
                            Color.white.opacity(0.1)
                                .aspectRatio(1.0, contentMode: .fill)
                                .overlay(ProgressView())
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .aspectRatio(1.0, contentMode: .fill)
                                .clipped()
                                .transition(.opacity)
                        case .failure:
                            Color.clear
                                .aspectRatio(1.0, contentMode: .fill)
                                .onAppear {
                                    if totalImages > 1 {
                                        inferenceEngine.dropInvalidCarouselImage(urlString)
                                        if selectedIndex >= totalImages - 1 {
                                            selectedIndex = max(0, totalImages - 2)
                                        }
                                    }
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .tag(liveCount + validHistoricImagePaths.count + index)
                }
            }
        }
    }
    
    // MARK: - Pagination Dots
    @ViewBuilder
    var paginationDots: some View {
        if totalImages > 1 {
            HStack(spacing: 8) {
                ForEach(0..<totalImages, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 16)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
        }
    }
}
