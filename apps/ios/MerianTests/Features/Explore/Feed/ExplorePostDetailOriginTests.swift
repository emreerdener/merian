import XCTest

@testable import Merian

final class ExplorePostDetailOriginTests: XCTestCase {
    private func makeRoute(origin: ExplorePostDetailOrigin) -> ExplorePostRoute {
        ExplorePostRoute(
            postId: "post-origin",
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            origin: origin
        )
    }

    func testOnlyMainFeedOriginEnablesObservationMapNavigation() {
        XCTAssertTrue(makeRoute(origin: .feed).allowsObservationMapNavigation)
        XCTAssertFalse(makeRoute(origin: .map).allowsObservationMapNavigation)
        XCTAssertFalse(makeRoute(origin: .other).allowsObservationMapNavigation)
    }
}
