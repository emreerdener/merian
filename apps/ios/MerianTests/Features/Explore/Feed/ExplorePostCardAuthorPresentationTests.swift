import XCTest

@testable import Merian

final class ExplorePostCardAuthorPresentationTests: XCTestCase {
    func testRemoteAuthorAvatarTakesPrecedenceOverViewerFallback() {
        let viewerAvatarURL = URL(string: "https://example.com/viewer.jpg")!

        let presentation = ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: "https://example.com/author.jpg",
            authorUserID: "viewer-id",
            authorIsPro: false,
            isOwnedByViewer: true,
            viewer: ExplorePostCardViewerContext(
                userID: "viewer-id",
                avatarURL: viewerAvatarURL,
                isSubscribed: false
            )
        )

        XCTAssertEqual(
            presentation.avatarURL,
            URL(string: "https://example.com/author.jpg")
        )
    }

    func testCurrentViewerAvatarFillsMissingAuthorAvatar() {
        let viewerAvatarURL = URL(string: "https://example.com/viewer.jpg")!

        let presentation = ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: nil,
            authorUserID: "viewer-id",
            authorIsPro: false,
            isOwnedByViewer: false,
            viewer: ExplorePostCardViewerContext(
                userID: "viewer-id",
                avatarURL: viewerAvatarURL,
                isSubscribed: false
            )
        )

        XCTAssertEqual(presentation.avatarURL, viewerAvatarURL)
    }

    func testAnotherAuthorDoesNotReceiveViewerAvatarFallback() {
        let presentation = ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: nil,
            authorUserID: "another-author",
            authorIsPro: false,
            isOwnedByViewer: false,
            viewer: ExplorePostCardViewerContext(
                userID: "viewer-id",
                avatarURL: URL(string: "https://example.com/viewer.jpg"),
                isSubscribed: false
            )
        )

        XCTAssertNil(presentation.avatarURL)
    }

    func testProPresentationPreservesAuthorAndOwnedSubscriberRules() {
        let subscribedViewer = ExplorePostCardViewerContext(
            userID: "viewer-id",
            avatarURL: nil,
            isSubscribed: true
        )

        let serverPro = ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: nil,
            authorUserID: "another-author",
            authorIsPro: true,
            isOwnedByViewer: false,
            viewer: subscribedViewer
        )
        let ownedSubscriber = ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: nil,
            authorUserID: "viewer-id",
            authorIsPro: false,
            isOwnedByViewer: true,
            viewer: subscribedViewer
        )
        let unownedSubscriber = ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: nil,
            authorUserID: "another-author",
            authorIsPro: false,
            isOwnedByViewer: false,
            viewer: subscribedViewer
        )

        XCTAssertTrue(serverPro.showsProBadge)
        XCTAssertTrue(ownedSubscriber.showsProBadge)
        XCTAssertFalse(unownedSubscriber.showsProBadge)
    }
}
