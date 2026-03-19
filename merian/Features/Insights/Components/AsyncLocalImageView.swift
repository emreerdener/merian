import SwiftUI

// MARK: - Lazy Loading Detached Image Renderer 
struct AsyncLocalImageView: View {
    let imagePath: String
    var fallbackImageUrl: String? = nil
    
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
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    
                    VStack(spacing: 4) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Visuals Archived")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
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
        
        // 1. RAM Cache Hit (Instant 0ms load)
        if let cached = ImageCache.shared.get(forKey: imagePath) {
            self.loadedImage = cached
            return
        }
        
        let fileName = (imagePath as NSString).lastPathComponent
        let url = URL.documentsDirectory.appendingPathComponent(fileName)
        Task {
            if let decoded = await Task.detached(priority: .userInitiated, operation: {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024
                ]
                
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                    return nil as UIImage?
                }
                
                return UIImage(cgImage: cgImage)
            }).value {
                // 2. Save to RAM Cache
                ImageCache.shared.set(decoded, forKey: imagePath)
                
                await MainActor.run {
                    self.loadedImage = decoded
                }
            } else if let fallbackUrlString = fallbackImageUrl, let fallbackUrl = URL(string: fallbackUrlString) {
                // 3. Network Fallback hook precisely mirrored from Scans grids
                if let networkImage = await fetchNetworkFallback(url: fallbackUrl, cacheKey: imagePath) {
                    await MainActor.run { self.loadedImage = networkImage }
                } else {
                    await MainActor.run { self.hasFailedToLoad = true }
                }
            } else {
                await MainActor.run { self.hasFailedToLoad = true }
            }
        }
    }
}
