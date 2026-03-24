import SwiftUI

struct ScanThumbnail: View {
    // MARK: - Asset Dependencies
    let imagePath: String?
    var fallbackImageUrl: String? = nil
    var maxDimension: Int = 600

    // MARK: - Rendering State
    @State private var thumbnail: UIImage? = nil
    @State private var hasFailedToLoad: Bool = false

    // MARK: - Visual Hierarchy
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
                let img = await LocalImageLoader.shared.loadImage(fromPath: imagePath, fallbackUrl: fallbackImageUrl, maxDimension: maxDimension)
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
