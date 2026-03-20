import SwiftUI

// MARK: - Lazy Loading Detached Image Renderer 
struct AsyncLocalImageView: View {
    let imagePath: String
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
                .aspectRatio(1.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
            } else {
                ProgressView()
                    .aspectRatio(1.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
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
