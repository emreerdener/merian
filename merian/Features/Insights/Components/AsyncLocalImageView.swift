import SwiftUI

struct AsyncLocalImageView: View {
    let path: String?
    var fallbackImageUrl: String? = nil
    var onImageLoadFailed: (() -> Void)? = nil

    @State private var loadedImage: UIImage? = nil
    @State private var hasFailedToLoad: Bool = false

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if hasFailedToLoad {
                ArchivedVisualsView()
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: loadedImage != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // task(id:) cancels the in-flight load when the view disappears during a fast swipe,
        // preventing multiple concurrent decode tasks from racing and stalling the main thread.
        .task(id: "\(path ?? "")|\(fallbackImageUrl ?? "")") {
            loadedImage = nil
            hasFailedToLoad = false
            let img = await LocalImageLoader.shared.loadImage(fromPath: path, fallbackUrl: fallbackImageUrl, maxDimension: Int(MerianConfig.displayImageMaxSize))
            guard !Task.isCancelled else { return }
            if let img {
                loadedImage = img
            } else {
                hasFailedToLoad = true
                onImageLoadFailed?()
            }
        }
    }
}
