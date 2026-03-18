import SwiftUI

struct LifeListThumbnailView: View {
    let imagePath: String?
    var fallbackImageUrl: String? = nil
    
    @State private var thumbnail: UIImage? = nil
    @State private var hasFailedToLoad: Bool = false
    
    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .overlay(
                Group {
                    if let uiImage = thumbnail {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else if hasFailedToLoad {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                            
                            VStack(spacing: 4) {
                                Image(systemName: "archivebox.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Visuals archived")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
            )
            .clipped()
        .task(id: imagePath ?? fallbackImageUrl ?? UUID().uuidString) {
            if thumbnail == nil {
                let cacheKey = imagePath ?? fallbackImageUrl ?? UUID().uuidString
                // 1. Check RAM immediately for existing decoded array bytes
                if let cached = ImageCache.shared.get(forKey: cacheKey) {
                    self.thumbnail = cached
                    return
                }
                
                // 2. Local File extraction attempting to load natively
                if let safePath = imagePath {
                    let filename = (safePath as NSString).lastPathComponent
                    let fullPathURL = URL.documentsDirectory.appendingPathComponent(filename)
                    if let generatedThumb = await generateThumbnail(for: fullPathURL, cacheKey: cacheKey) {
                        await MainActor.run { self.thumbnail = generatedThumb }
                        return
                    }
                }
                
                // 3. Local File is Missing/Archived off R2 -> trigger robust network fallback
                if let fallbackUrlString = fallbackImageUrl, let fallbackUrl = URL(string: fallbackUrlString) {
                    if let networkImage = await fetchNetworkFallback(url: fallbackUrl, cacheKey: cacheKey) {
                        await MainActor.run { self.thumbnail = networkImage }
                    } else {
                        await MainActor.run { self.hasFailedToLoad = true }
                    }
                } else {
                    await MainActor.run { self.hasFailedToLoad = true }
                }
            }
        }
    }
}
