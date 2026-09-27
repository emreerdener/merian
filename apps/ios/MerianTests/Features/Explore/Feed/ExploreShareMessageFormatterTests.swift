import XCTest

@testable import Merian

final class ExploreShareMessageFormatterTests: XCTestCase {
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
