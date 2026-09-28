import XCTest
import UIKit

@testable import Merian

final class ExploreShareMessageFormatterTests: XCTestCase {
    func testPreviewUsesOnlyPostImagesOrPersistedPosters() {
        let video = ExploreMediaItem(
            kind: .video, url: "https://example.com/video.mp4",
            thumbnailUrl: "https://example.com/poster.jpg", orderIndex: 1,
            durationSeconds: 4, hasAudio: true
        )
        let image = ExploreMediaItem(
            kind: .image, url: "https://example.com/photo.jpg", thumbnailUrl: nil,
            orderIndex: 0, durationSeconds: nil, hasAudio: false
        )
        XCTAssertEqual(
            ExploreShareMessageFormatter.previewImageURL(heroImageURL: " https://example.com/hero.jpg ", mediaItems: [video, image]),
            "https://example.com/hero.jpg"
        )
        XCTAssertEqual(
            ExploreShareMessageFormatter.previewImageURL(heroImageURL: " ", mediaItems: [video, image]),
            image.url
        )
        XCTAssertEqual(
            ExploreShareMessageFormatter.previewImageURL(heroImageURL: "", mediaItems: [video]),
            video.thumbnailUrl
        )
        for kind in [ExploreMediaKind.audio, .video] {
            let media = ExploreMediaItem(
                kind: kind, url: "https://example.com/recording", thumbnailUrl: nil,
                orderIndex: 0, durationSeconds: 4, hasAudio: true
            )
            XCTAssertNil(ExploreShareMessageFormatter.previewImageURL(heroImageURL: "", mediaItems: [media]))
        }
        let audio = ExploreMediaItem(
            kind: .audio, url: "https://example.com/audio.wav",
            thumbnailUrl: "https://example.com/spectrogram.png", orderIndex: 0,
            durationSeconds: 4, hasAudio: true
        )
        XCTAssertEqual(
            ExploreShareMessageFormatter.previewImageURL(heroImageURL: "", mediaItems: [audio]),
            audio.thumbnailUrl
        )
        XCTAssertNil(ExploreShareMessageFormatter.previewImageURL(heroImageURL: "", mediaItems: []))
    }

    @MainActor
    func testSharePreviewLoadsThePostHeroThroughTheBoundedImageLoader() async throws {
        let post = ExploreFeedTestFixtures.post(id: "share-preview")
        let source = ExploreShareMessageFormatter.itemSource(
            post: post,
            commonName: "Northern Cardinal",
            images: ExploreHeroImageDependencies { url, maxDimension in
                XCTAssertEqual(url, "https://example.com/share-preview.jpg")
                XCTAssertEqual(maxDimension, 1024)
                return nil
            }
        )
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        let metadata = try XCTUnwrap(source.activityViewControllerLinkMetadata(controller))
        let provider = try XCTUnwrap(metadata.imageProvider)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = provider.loadObject(ofClass: UIImage.self) { _, error in
                XCTAssertNotNil(error)
                continuation.resume()
            }
        }
        XCTAssertEqual(metadata.title, "Check out this Northern Cardinal")
        XCTAssertEqual(metadata.url, ExploreShareMessageFormatter.url(postId: post.id))
    }

    func testPostDestinationIsATypedCanonicalURL() {
        let url = ExploreShareMessageFormatter.url(postId: "post-123")
        XCTAssertEqual(url.absoluteString, "https://naturebook.earth/explore/post/post-123")
        XCTAssertEqual(url.scheme, "https")
    }

    func testImageAndVideoMessagesUseContentFirstCopy() {
        for mediaKind in [ExploreMediaKind.image, .video] {
            XCTAssertEqual(
                ExploreShareMessageFormatter.title(
                    commonName: "Northern Cardinal",
                    primaryMediaKind: mediaKind
                ),
                "Check out this Northern Cardinal"
            )
        }
    }

    func testAudioMessageInvitesRecipientToListen() {
        XCTAssertEqual(
            ExploreShareMessageFormatter.title(
                commonName: "Northern Cardinal",
                primaryMediaKind: .audio
            ),
            "Listen to this Northern Cardinal"
        )
    }

    func testMissingMediaUsesCheckOutFallback() {
        XCTAssertEqual(
            ExploreShareMessageFormatter.title(
                commonName: "Northern Cardinal",
                primaryMediaKind: nil
            ),
            "Check out this Northern Cardinal"
        )
    }

    func testPrimaryMediaKindControlsMixedMediaCopy() {
        let mediaItems = [
            ExploreMediaItem(
                kind: .video,
                url: "https://example.com/cardinal.mp4",
                thumbnailUrl: nil,
                orderIndex: 0,
                durationSeconds: 4,
                hasAudio: true
            ),
            ExploreMediaItem(
                kind: .audio,
                url: "https://example.com/cardinal.m4a",
                thumbnailUrl: nil,
                orderIndex: 1,
                durationSeconds: 8,
                hasAudio: true
            )
        ]

        XCTAssertEqual(
            ExploreShareMessageFormatter.title(
                commonName: "Northern Cardinal",
                primaryMediaKind: mediaItems.first?.kind
            ),
            "Check out this Northern Cardinal"
        )
    }

    func testMessageExcludesAppScientificLocationAndAuthorCopy() {
        let message = ExploreShareMessageFormatter.title(
            commonName: "Northern Cardinal",
            primaryMediaKind: .image
        )

        XCTAssertFalse(message.contains("Merian"))
        XCTAssertFalse(message.contains("Explore post"))
        XCTAssertFalse(message.contains("Cardinalis cardinalis"))
        XCTAssertFalse(message.contains("Chicago"))
        XCTAssertFalse(message.contains("@author"))
    }
}
