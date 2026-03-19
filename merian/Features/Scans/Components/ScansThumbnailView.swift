import SwiftUI

struct ScansThumbnailView: View {
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
                let img = await LocalImageLoader.shared.loadImage(fromPath: imagePath, fallbackUrl: fallbackImageUrl)
                await MainActor.run {
                    if let img = img {
                        self.thumbnail = img
                    } else {
                        self.hasFailedToLoad = true
                    }
                }
            }
        }
    }
}
