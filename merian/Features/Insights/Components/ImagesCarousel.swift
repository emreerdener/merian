import SwiftUI

struct ImagesCarousel: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    
    // MARK: - State
    @State private var selectedIndex: Int = 0
    
    // MARK: - Computed Boundaries
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
                    .id("ImagesCarousel_\(totalImages)_\(inferenceEngine.speciesData?.scanId ?? "null")")
                    .ignoresSafeArea(edges: .top) // Prevent internal TabView safe-area squashing!
                    .clipped() // Ensure the image layer natively truncates inside its own view logic alone
                    .overlay(alignment: .bottom) { paginationDots }
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
    
    // MARK: - Action Handlers
    private func handleImageFailure(identifier: String) {
        if totalImages > 1 {
            inferenceEngine.dropInvalidCarouselImage(identifier)
            if selectedIndex >= totalImages - 1 {
                selectedIndex = max(0, totalImages - 2)
            }
        }
    }
}

// MARK: - Layout Subcomponents
private extension ImagesCarousel {
    
    @ViewBuilder
    var imageTabs: some View {
        TabView(selection: $selectedIndex) {
            // Priority: Live Capture actively evaluated (Data payload)
            if hasLive, let livePayload = inferenceEngine.activeImageData, let uiImage = UIImage(data: livePayload) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .tag(0)
            }
            
            // User's Uploaded Images
            ForEach(Array(validHistoricImagePaths.enumerated()), id: \.offset) { index, path in
                AsyncLocalImageView(
                    imagePath: path,
                    onImageLoadFailed: { handleImageFailure(identifier: path) }
                )
                .tag(liveCount + index)
            }
            
            // Tab 1+: Wikipedia / GBIF Reference Images
            ForEach(Array(refUrls.enumerated()), id: \.offset) { index, urlString in
                AsyncLocalImageView(
                    imagePath: nil,
                    fallbackImageUrl: urlString,
                    onImageLoadFailed: { handleImageFailure(identifier: urlString) }
                )
                .tag(liveCount + validHistoricImagePaths.count + index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .aspectRatio(1.0, contentMode: .fill)
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
            .padding(.bottom, 40)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
        }
    }
}

// MARK: - Lazy Loading Detached Image Renderer 
private struct AsyncLocalImageView: View {
    let imagePath: String?
    var fallbackImageUrl: String? = nil
    var onImageLoadFailed: (() -> Void)? = nil
    
    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad: Bool = false
    
    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(1.0, contentMode: .fill)
                    .clipped()
            } else if hasFailedToLoad {
                ArchivedVisualsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1.0, contentMode: .fill)
                .clipped()
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.1))
                    .aspectRatio(1.0, contentMode: .fill)
                    .clipped()
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard loadedImage == nil else { return }
        Task {
            let img = await LocalImageLoader.shared.loadImage(fromPath: imagePath, fallbackUrl: fallbackImageUrl)
            await MainActor.run {
                if let img = img {
                    self.loadedImage = img
                } else {
                    self.hasFailedToLoad = true
                    self.onImageLoadFailed?()
                }
            }
        }
    }
}
