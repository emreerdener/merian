import SwiftUI

struct AsyncLocalImageView: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let path: String?
    var fallbackImageUrl: String?
    var contentMode: ContentMode = .fill
    var fillHeight: Bool = false
    var isArchivedVisual: Bool = false
    var onImageLoaded: (() -> Void)?
    var onImageLoadFailed: (() -> Void)?

    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad: Bool = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let img = loadedImage {
                    imageView(for: img, in: proxy.size)
                } else if hasFailedToLoad {
                    if isArchivedVisual {
                        ArchivedVisualsView()
                    } else {
                        UnavailableVisualsView(isOffline: !offlineQueueManager.isOnline)
                    }
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.3), value: loadedImage != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // task(id:) cancels the in-flight load when the view disappears during a fast swipe,
        // preventing multiple concurrent decode tasks from racing and stalling the main thread.
        .task(id: loadTaskID) {
            loadedImage = nil
            hasFailedToLoad = false
            let img = await LocalImageLoader.shared.loadImage(fromPath: path, fallbackUrl: fallbackImageUrl, maxDimension: Int(MerianConfig.displayImageMaxSize))
            guard !Task.isCancelled else { return }
            if let img {
                loadedImage = img
                onImageLoaded?()
            } else {
                hasFailedToLoad = true
                onImageLoadFailed?()
            }
        }
    }

    private var loadTaskID: String {
        "\(path ?? "")|\(fallbackImageUrl ?? "")|\(remoteRetryTaskKey)"
    }

    private var remoteRetryTaskKey: String {
        guard hasRemoteVisualSource else { return "local_media" }
        return offlineQueueManager.isOnline ? "remote_online" : "remote_offline"
    }

    private var hasRemoteVisualSource: Bool {
        [path, fallbackImageUrl]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    @ViewBuilder
    private func imageView(for image: UIImage, in containerSize: CGSize) -> some View {
        if fillHeight {
            let safeImageHeight = max(image.size.height, 1)
            let width = containerSize.height * (image.size.width / safeImageHeight)

            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: containerSize.height)
                .frame(width: containerSize.width, height: containerSize.height, alignment: .center)
                .transition(.opacity)
        } else if contentMode == .fill {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .transition(.opacity)
        }
    }
}
