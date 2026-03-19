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
                        ArchivedVisualsView()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
            )
            .clipped()
        .task(id: imagePath ?? fallbackImageUrl ?? "empty_thumbnail_state") {
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
