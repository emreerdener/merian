import SwiftUI

struct ImagesCarousel: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    
    // MARK: - Properties
    let scanId: String?
    let refUrls: [String]
    let validHistoricImagePaths: [String]
    let hasLive: Bool
    let liveCount: Int
    let totalImages: Int
    
    // MARK: - State
    @State private var selectedIndex: Int? = 0
    
    // MARK: - Body
    var body: some View {
        if totalImages > 0 {
            VStack(spacing: 0) {
                TabView(selection: Binding(
                    get: { selectedIndex ?? 0 },
                    set: { selectedIndex = $0 }
                )) {
                    // Priority: Live Capture actively evaluated (Data payload)
                    if hasLive {
                        ForEach(Array(inferenceEngine.activeLiveCaptureDatas.enumerated()), id: \.offset) { index, data in
                            if let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .clipped()
                                    .tag(index)
                            }
                        }
                    }
                    
                    // User's Uploaded Images
                    ForEach(Array(validHistoricImagePaths.enumerated()), id: \.offset) { index, path in
                        AsyncLocalImageView(
                            path: path,
                            fallbackImageUrl: nil,
                            onImageLoadFailed: { handleImageFailure(identifier: path) }
                        )
                        .tag(liveCount + index)
                    }
                    
                    // Tab 1+: Wikipedia / GBIF Reference Images
                    ForEach(Array(refUrls.enumerated()), id: \.offset) { index, urlString in
                        AsyncLocalImageView(
                            path: "",
                            fallbackImageUrl: urlString,
                            onImageLoadFailed: { handleImageFailure(identifier: urlString) }
                        )
                        .tag(liveCount + validHistoricImagePaths.count + index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id("ImagesCarousel_\(totalImages)_\(scanId ?? "null")")
                .ignoresSafeArea(edges: .top) // Prevent internal TabView safe-area squashing!
                .clipped() // Ensure the image layer natively truncates inside its own view logic alone
                .overlay(alignment: .bottom) { paginationDots }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea(.all, edges: .top) // CRUESCIAL: Enables the VStack to puncture the sheet padding exactly where the parent geometry reader calls it!
        }
    }
    
    // MARK: - Action Handlers
    private func handleImageFailure(identifier: String) {
        if totalImages > 1 {
            inferenceEngine.dropInvalidCarouselImage(identifier)
            if (selectedIndex ?? 0) >= totalImages - 1 {
                selectedIndex = max(0, totalImages - 2)
            }
        }
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {
    
    // MARK: - Pagination Dots
    @ViewBuilder
    var paginationDots: some View {
        if totalImages > 1 {
            HStack(spacing: 8) {
                ForEach(0..<totalImages, id: \.self) { index in
                    Circle()
                        .fill(index == (selectedIndex ?? 0) ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 40)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex ?? 0)
        }
    }
}
