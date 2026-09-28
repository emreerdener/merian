import LinkPresentation
import UIKit

/// Keeps the shared item a URL for AirDrop, Copy, and third-party extensions.
/// Descriptive copy belongs in preview metadata and the optional mail subject.
/// UIActivityItemSource has nonisolated requirements. Stored values are immutable,
/// and each metadata callback creates a fresh object without accessing UI state.
final class LinkShareItemSource: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    private let previewImageLoader: (@Sendable () async -> UIImage?)?

    init(
        url: URL,
        title: String,
        previewImageLoader: (@Sendable () async -> UIImage?)? = nil
    ) {
        self.url = url
        self.title = title
        self.previewImageLoader = previewImageLoader
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        if let previewImageLoader {
            let provider = NSItemProvider()
            provider.registerObject(ofClass: UIImage.self, visibility: .all) { completion in
                let progress = Progress(totalUnitCount: 1)
                let task = Task {
                    let image = await previewImageLoader()
                    if Task.isCancelled {
                        completion(nil, CancellationError())
                    } else if let image {
                        completion(image, nil)
                    } else {
                        completion(nil, CocoaError(.fileReadUnknown))
                    }
                    progress.completedUnitCount = 1
                }
                progress.cancellationHandler = { task.cancel() }
                return progress
            }
            metadata.imageProvider = provider
        }
        return metadata
    }
}
