import Foundation
import UIKit
import WidgetKit

private struct ExploreWidgetSourcePost: Sendable, Equatable {
    let postId: String
    let heroImageUrl: String
    let sharedAt: String
    let speciesCommonName: String
    let speciesScientificName: String
}

/// A suspended image request can commit only for the current write and account.
@MainActor
final class ExploreWidgetWriteGate {
    struct Token {
        let generation: UInt64
        let visibility: ExploreContentVisibilityStore.Context
    }
    private var generation: UInt64 = 0

    func invalidate() { generation &+= 1 }

    func begin(visibility: ExploreContentVisibilityStore.Context) -> Token {
        invalidate()
        return Token(generation: generation, visibility: visibility)
    }

    func accepts(_ token: Token, visibility: ExploreContentVisibilityStore.Context) -> Bool {
        !Task.isCancelled && token.generation == generation && token.visibility == visibility
    }
}

@MainActor
enum ExploreWidgetSnapshotWriter {
    private static var pendingWrite: Task<Void, Never>?
    private static let writeGate = ExploreWidgetWriteGate()
    private static var snapshotViewerID: UUID?

    static func invalidate(visibility: ExploreContentVisibilityStore) {
        pendingWrite?.cancel()
        writeGate.invalidate()
        let accountChanged = snapshotViewerID != visibility.viewerID
        snapshotViewerID = visibility.viewerID
        let items = accountChanged ? [] : (ExploreWidgetCache.loadSnapshot()?.items ?? []).filter {
            visibility.isVisible(postID: $0.postId)
        }
        let snapshot = ExploreWidgetSnapshot(updatedAt: Date(), items: items)
        do {
            try ExploreWidgetCache.writeSnapshot(snapshot)
            ExploreWidgetCache.removeImagesNotInSnapshot(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: ExploreWidgetConstants.kind)
        } catch {
            // Remove the stale manifest if replacing it fails.
            if let url = ExploreWidgetConstants.snapshotURL() { try? FileManager.default.removeItem(at: url) }
            WidgetCenter.shared.reloadTimelines(ofKind: ExploreWidgetConstants.kind)
        }
    }

    @MainActor
    static func refreshRecentFeedSnapshot(from posts: [ExplorePost]) {
        let visibility = AppDIContainer.shared.exploreContentVisibility
        pendingWrite?.cancel()
        let token = writeGate.begin(visibility: visibility.context)
        let sourcePosts = posts.filter { visibility.isVisible(postID: $0.id) }
            .filter { post in
                post.resolvedMediaItems.contains {
                    $0.kind == .image || $0.kind == .video
                }
            }
            .prefix(ExploreWidgetConstants.maxItemCount)
            .compactMap { post -> ExploreWidgetSourcePost? in
                guard !post.postId.isEmpty, !post.heroImageUrl.isEmpty else { return nil }
                return ExploreWidgetSourcePost(
                    postId: post.postId,
                    heroImageUrl: post.heroImageUrl,
                    sharedAt: post.sharedAt,
                    speciesCommonName: post.speciesCommonName,
                    speciesScientificName: post.speciesScientificName
                )
            }

        pendingWrite = Task(priority: .utility) {
            await writeSnapshot(from: sourcePosts, visibility: visibility, token: token)
        }
    }

    private static func writeSnapshot(
        from sourcePosts: [ExploreWidgetSourcePost], visibility: ExploreContentVisibilityStore,
        token: ExploreWidgetWriteGate.Token
    ) async {
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

            guard writeGate.accepts(token, visibility: visibility.context) else { return }
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
                        speciesScientificName: post.speciesScientificName
                    )
                )
            } catch {
                continue
            }
        }

        guard writeGate.accepts(token, visibility: visibility.context) else { return }

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
