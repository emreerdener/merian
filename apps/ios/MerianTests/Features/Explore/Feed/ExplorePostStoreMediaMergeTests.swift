import XCTest

@testable import Merian

@MainActor
final class ExplorePostStoreMediaMergeTests: XCTestCase {
    func testUpsertPreservesExistingVideoMediaWhenRefreshOmitsMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.upsert(makePost(mediaItems: [videoItem]), includeInFeed: true)
        store.upsert(makePost(mediaItems: nil))

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    func testUpsertPreservesExistingVideoMediaWhenRefreshUsesEmptyMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.upsert(makePost(mediaItems: [videoItem]), includeInFeed: true)
        store.upsert(makePost(mediaItems: []))

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    func testUpsertUsesIncomingMediaItemsWhenPresent() {
        let store = ExplorePostStore()
        let oldVideoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/old-video.mp4",
            thumbnailUrl: "https://media.example/old-poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )
        let newImageItem = ExploreMediaItem(
            kind: .image,
            url: "https://media.example/new-image.jpg",
            thumbnailUrl: "https://media.example/new-image.jpg",
            orderIndex: 0,
            durationSeconds: nil,
            hasAudio: false
        )

        store.upsert(makePost(mediaItems: [oldVideoItem]), includeInFeed: true)
        store.upsert(makePost(mediaItems: [newImageItem]))

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [newImageItem])
    }

    func testFeedRefreshPreservesExistingVideoMediaWhenPayloadOmitsMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.setFeedPosts([makePost(mediaItems: [videoItem])])
        store.setFeedPosts([makePost(mediaItems: nil)])

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    func testAppendingFeedPostPreservesSupplementalVideoMediaWhenPayloadOmitsMediaItems() {
        let store = ExplorePostStore()
        let videoItem = ExploreMediaItem(
            kind: .video,
            url: "https://media.example/video.mp4",
            thumbnailUrl: "https://media.example/poster.jpg",
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )

        store.upsert(makePost(mediaItems: [videoItem]))
        store.appendUniqueFeedPosts([makePost(mediaItems: nil)])

        XCTAssertEqual(store.post(id: "post-1")?.resolvedMediaItems, [videoItem])
    }

    private func makePost(mediaItems: [ExploreMediaItem]?) -> ExplorePost {
        ExplorePost(
            postId: "post-1",
            scanId: "scan-1",
            heroImageUrl: "https://media.example/hero.jpg",
            sharedAt: "2026-07-08T00:00:00Z",
            authorUserId: "author-1",
            authorName: "Test Author",
            authorUsername: "author",
            authorAvatarUrl: nil,
            authorIsPro: false,
            hashtags: nil,
            speciesCommonName: "Great Blue Heron",
            speciesScientificName: "Ardea herodias",
            petIdentification: nil,
            publicLocationLabel: "Austin, TX",
            locationSharing: nil,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false,
            rankingValue: nil,
            mediaItems: mediaItems
        )
    }
}
