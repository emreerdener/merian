import SwiftUI
import SafariServices

// MARK: - Safari View Wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {}
}

// MARK: - Helper Views
struct BadgeView: View {
    let text: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(12)
    }
}

struct TaxonomyNode: View {
    let level: String
    let name: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(level)
                .font(.caption2)
                .bold()
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

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
        
        let url = URL.documentsDirectory.appendingPathComponent(imagePath)
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
                // 3. Network Fallback hook precisely mirrored from Life List grids
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
