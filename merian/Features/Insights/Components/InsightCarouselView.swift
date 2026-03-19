import SwiftUI

struct InsightCarouselView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
        let validHistoricImagePaths = inferenceEngine.validHistoricImagePaths
        let totalImages = (inferenceEngine.activeImageData != nil ? 1 : 0) + validHistoricImagePaths.count + refUrls.count
        
        if totalImages > 0 {
            TabView {
                // Priority: Live Capture actively evaluated (Data payload)
                if let livePayload = inferenceEngine.activeImageData, let uiImage = UIImage(data: livePayload) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1.0, contentMode: .fill)
                        .clipped()
                        .tag("user_image_live")
                }
                
                // User's Uploaded Images (Historic Pipeline deferred by path cleanly preventing OOMs natively)
                ForEach(Array(validHistoricImagePaths.enumerated()), id: \.element) { index, path in
                    AsyncLocalImageView(imagePath: path)
                    .tag("user_image_\(index)")
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
                                Color.white.opacity(0.1)
                                    .aspectRatio(1.0, contentMode: .fill)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.gray.opacity(0.5))
                                    )
                                    .transition(.opacity)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .tag("ref_\(index)")
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: totalImages > 1 ? .always : .never))
            // CRITICAL FIX: Explicitly prevents EXC_CRASH (SIGABRT) deep implicitly inside _ViewList_SubgraphRelease by coercing SwiftUI
            // to entirely destroy and reconstruct the core underlying native UICollectionView boundaries if array sizing inherently mutates structurally.
            .id("InsightCarousel_\(totalImages)_\(inferenceEngine.speciesData?.scanId ?? "null")")
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
}
