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
    // Non-optional avoids an inline Binding(get:set:) wrapper that recreates on every render.
    @State private var selectedIndex: Int = 0

    // MARK: - Body
    var body: some View {
        if totalImages > 0 {
            VStack(spacing: 0) {
                TabView(selection: $selectedIndex) {
                    // Priority: Live Capture actively evaluated (Data payload)
                    if hasLive {
                        ForEach(Array(inferenceEngine.activeLiveCaptureDatas.enumerated()), id: \.offset) { index, data in
                            LiveCapturePageView(data: data)
                                .tag(index)
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
                            path: nil,
                            fallbackImageUrl: urlString,
                            onImageLoadFailed: { handleImageFailure(identifier: urlString) }
                        )
                        .tag(liveCount + validHistoricImagePaths.count + index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // scanId only — totalImages changes async when validHistoricImagePaths resolves,
                // which would destroy and recreate the TabView mid-swipe and snap back to page 0.
                .id(scanId ?? "null")
                .ignoresSafeArea(edges: .top)
                .clipped()
                .overlay(alignment: .bottom) { paginationDots }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea(.all, edges: .top)
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

// MARK: - Live Capture Page
/// Decodes raw Data → UIImage in a background task so the main thread is never blocked
/// during render, preventing frame drops when the carousel first opens.
private struct LiveCapturePageView: View {
    let data: Data
    @State private var decoded: UIImage? = nil

    var body: some View {
        Group {
            if let img = decoded {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task {
            decoded = UIImage(data: data)
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
