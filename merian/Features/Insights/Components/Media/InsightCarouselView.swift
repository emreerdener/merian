import SwiftUI

struct InsightCarouselView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @State private var selectedIndex: Int = 0
    private let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    
    // MARK: - Computed State Data Loaders
    private var refUrls: [String] {
        inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
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
                    .onReceive(timer) { _ in
                        if totalImages > 1 {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                selectedIndex = (selectedIndex + 1) % totalImages
                            }
                        }
                    }
                    .id("InsightCarousel_\(totalImages)_\(inferenceEngine.speciesData?.scanId ?? "null")")
                    .aspectRatio(1.0, contentMode: .fill)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),   // Anchor opaque at top
                                .init(color: .black, location: 0.8),   // Hold fully opaque down to exactly 80%
                                .init(color: .clear, location: 1.0)    // Rapidly fade to clear only in the final 20%
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipped() // Ensure the image layer natively truncates inside its own view logic alone
                    .overlay(alignment: .bottom) { paginationDots }
                
                metadataStraddleOverlay
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
            ForEach(Array(validHistoricImagePaths.enumerated()), id: \.element) { index, path in
                AsyncLocalImageView(imagePath: path)
                    .tag(liveCount + index)
            }
            
            // Tab 1+: Wikipedia / GBIF Reference Images
            ForEach(Array(refUrls.enumerated()), id: \.element) { index, urlString in
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
            .padding(.bottom, 40)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
        }
    }
    
    private var hasWeather: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return inferenceEngine.speciesData?.weatherTemperatureF != nil && inferenceEngine.speciesData?.weatherCondition != nil
        #endif
    }
    
    // MARK: - Metadata Straddle Overlay
    @ViewBuilder
    var metadataStraddleOverlay: some View {
        // Sub-Image Overlay extracted purely physically into structural space
        HStack(alignment: .top) {
            if hasWeather {
                // Left Side Confidence Badge and Location
                VStack(alignment: .leading, spacing: 8) {
                    ConfidenceBadgeView()
                    LocationBadgeView()
                }
                Spacer()
                // Right Side Weather
                WeatherBadgeView()
            } else {
                Spacer()
                // Centered Orientation when Weather is unavailable
                VStack(alignment: .center, spacing: 16) {
                    ConfidenceBadgeView()
                    LocationBadgeView()
                }
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, -24) // Synthesizes the exact overlap required!
        .padding(.bottom, 8)
        .zIndex(10) // Forces the straddling item strictly on top
    }
}
