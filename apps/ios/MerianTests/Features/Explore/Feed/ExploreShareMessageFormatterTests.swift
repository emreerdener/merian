import XCTest

@testable import Merian

final class ExploreShareMessageFormatterTests: XCTestCase {
    func testImageAndVideoMessagesUseContentFirstCopy() {
        for mediaKind in [ExploreMediaKind.image, .video] {
            XCTAssertEqual(
                ExploreShareMessageFormatter.message(
                    commonName: "Northern Cardinal",
                    postId: "post-123",
                    primaryMediaKind: mediaKind
                ),
                "Check out this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
            )
        }
    }

    func testAudioMessageInvitesRecipientToListen() {
        XCTAssertEqual(
            ExploreShareMessageFormatter.message(
                commonName: "Northern Cardinal",
                postId: "post-123",
                primaryMediaKind: .audio
            ),
            "Listen to this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
        )
    }

    func testMissingMediaUsesCheckOutFallback() {
        XCTAssertEqual(
            ExploreShareMessageFormatter.message(
                commonName: "Northern Cardinal",
                postId: "post-123",
                primaryMediaKind: nil
            ),
            "Check out this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
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
            ExploreShareMessageFormatter.message(
                commonName: "Northern Cardinal",
                postId: "post-123",
                primaryMediaKind: mediaItems.first?.kind
            ),
            "Check out this Northern Cardinal\nhttps://naturebook.earth/explore/post/post-123"
        )
    }

    func testMessageExcludesAppScientificLocationAndAuthorCopy() {
        let message = ExploreShareMessageFormatter.message(
            commonName: "Northern Cardinal",
            postId: "post-123",
            primaryMediaKind: .image
        )

        XCTAssertFalse(message.contains("Merian"))
        XCTAssertFalse(message.contains("Explore post"))
        XCTAssertFalse(message.contains("Cardinalis cardinalis"))
        XCTAssertFalse(message.contains("Chicago"))
        XCTAssertFalse(message.contains("@author"))
    }
}
