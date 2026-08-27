import XCTest

@testable import Merian

@MainActor
final class ExploreNotificationRowPresentationTests: XCTestCase {
    func testAggregatedLikeCopyPreservesActorOrderingAndOtherCount() {
        let notification = ExploreNotificationsTestFixtures.notification(
            id: "likes",
            type: .likeAggregated,
            recentActorNames: ["Avery", "Blair"],
            actionCount: 4
        )

        let presentation = ExploreNotificationRowPresentation(notification: notification)

        XCTAssertEqual(
            presentation.primaryText,
            "Avery, Blair, and 2 others liked your post."
        )
        XCTAssertNil(presentation.secondaryText)
        XCTAssertEqual(presentation.systemImage, "heart.fill")
        XCTAssertEqual(presentation.accent, .red)
        XCTAssertTrue(presentation.showsDisclosureIndicator)
    }

    func testReactionCopyTrimsNamesBodyAndIncludesEmoji() {
        let notification = ExploreNotificationsTestFixtures.notification(
            id: "reaction",
            type: .commentReaction,
            reactionEmoji: "🌿",
            commentBody: "  Thoughtful note  ",
            recentActorNames: ["  Avery  "],
            actionCount: 1
        )

        let presentation = ExploreNotificationRowPresentation(notification: notification)

        XCTAssertEqual(
            presentation.primaryText,
            "Avery reacted 🌿 to your comment."
        )
        XCTAssertEqual(presentation.secondaryText, "Thoughtful note")
        XCTAssertEqual(presentation.accent, .orange)
    }

    func testPostlessFollowRemainsInformational() {
        let notification = ExploreNotificationsTestFixtures.notification(
            id: "follow",
            type: .follow,
            postId: nil,
            commentId: nil,
            triggeringUserName: "  ",
            commentBody: nil
        )

        let presentation = ExploreNotificationRowPresentation(notification: notification)

        XCTAssertEqual(presentation.primaryText, "Someone followed you.")
        XCTAssertNil(presentation.secondaryText)
        XCTAssertEqual(presentation.systemImage, "person.crop.circle.badge.plus")
        XCTAssertEqual(presentation.accent, .green)
        XCTAssertFalse(presentation.showsDisclosureIndicator)
    }

    func testFieldTripReplyPreservesViewerSpecificWording() {
        let notification = ExploreNotificationsTestFixtures.notification(
            id: "outing-reply",
            type: .fieldTripReply,
            postId: nil,
            fieldTripPublicationId: "publication-1",
            triggeringUserName: "Avery",
            isReplyToViewerComment: true
        )

        let presentation = ExploreNotificationRowPresentation(notification: notification)

        XCTAssertEqual(
            presentation.primaryText,
            "Avery replied to your outing comment."
        )
        XCTAssertEqual(presentation.systemImage, "arrowshape.turn.up.left.fill")
        XCTAssertEqual(presentation.accent, .purple)
        XCTAssertTrue(presentation.showsDisclosureIndicator)
    }
}
