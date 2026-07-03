import Foundation
import UIKit
import WidgetKit

private struct ExploreWidgetSourcePost: Sendable, Equatable {
    let postId: String
    let heroImageUrl: String
    let sharedAt: String
    let speciesCommonName: String
    let speciesScientificName: String
    let hasVideo: Bool
}

enum ExploreWidgetSnapshotWriter {
    @MainActor
    static func refreshRecentFeedSnapshot(from posts: [ExplorePost]) {
        let sourcePosts = posts
            .prefix(ExploreWidgetConstants.maxItemCount)
            .compactMap { post -> ExploreWidgetSourcePost? in
                guard !post.postId.isEmpty, !post.heroImageUrl.isEmpty else { return nil }
                return ExploreWidgetSourcePost(
                    postId: post.postId,
                    heroImageUrl: post.heroImageUrl,
                    sharedAt: post.sharedAt,
                    speciesCommonName: post.speciesCommonName,
                    speciesScientificName: post.speciesScientificName,
                    hasVideo: post.hasVideoMedia
                )
            }

        guard !sourcePosts.isEmpty else { return }

        Task.detached(priority: .utility) {
            await writeSnapshot(from: sourcePosts)
        }
    }

    private static func writeSnapshot(from sourcePosts: [ExploreWidgetSourcePost]) async {
        let fileManager = FileManager.default
        guard let imageDirectoryURL = ExploreWidgetConstants.imageDirectoryURL(fileManager: fileManager) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: imageDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        var items: [ExploreWidgetItem] = []

        for (index, post) in sourcePosts.enumerated() {
            guard let imageData = await imageData(for: post.heroImageUrl) else {
                continue
            }

            let filename = ExploreWidgetConstants.imageFilename(
                postId: post.postId,
                index: index
            )
            let destinationURL = imageDirectoryURL.appendingPathComponent(filename)

            do {
                try imageData.write(to: destinationURL, options: [.atomic])
                items.append(
                    ExploreWidgetItem(
                        postId: post.postId,
                        imageFilename: filename,
                        sharedAt: post.sharedAt,
                        speciesCommonName: post.speciesCommonName,
                        speciesScientificName: post.speciesScientificName,
                        hasVideo: post.hasVideo
                    )
                )
            } catch {
                continue
            }
        }

        guard !items.isEmpty else { return }

        let snapshot = ExploreWidgetSnapshot(updatedAt: Date(), items: items)

        do {
            try ExploreWidgetCache.writeSnapshot(snapshot, fileManager: fileManager)
            ExploreWidgetCache.removeImagesNotInSnapshot(snapshot, fileManager: fileManager)
            WidgetCenter.shared.reloadTimelines(ofKind: ExploreWidgetConstants.kind)
        } catch {
            return
        }
    }

    private static func imageData(for heroImageUrl: String) async -> Data? {
        guard let image = await LocalImageLoader.shared.loadImage(
            fromPath: nil,
            fallbackUrl: heroImageUrl,
            maxDimension: ExploreWidgetConstants.imageMaxDimension
        ) else {
            return nil
        }

        return image.jpegData(
            compressionQuality: CGFloat(ExploreWidgetConstants.imageCompressionQuality)
        )
    }
}
