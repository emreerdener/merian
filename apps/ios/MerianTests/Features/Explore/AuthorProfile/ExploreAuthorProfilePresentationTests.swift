import XCTest

@testable import Merian

final class ExploreAuthorProfilePresentationTests: XCTestCase {
    func testProfileNavigationCanOpenAtRootButStopsAtMaxDepth() {
        XCTAssertTrue(ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: 0))
        XCTAssertFalse(
            ExploreAuthorProfileNavigationPolicy.canOpenProfile(
                from: ExploreAuthorProfileNavigationPolicy.maxProfileDepth
            )
        )
    }

    func testProfileNavigationDepthCapsAtMaxDepth() {
        XCTAssertEqual(ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: 0), 1)
        XCTAssertEqual(
            ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: 1),
            ExploreAuthorProfileNavigationPolicy.maxProfileDepth
        )
    }

    func testLibraryTitleUsesViewerAndPossessivePresentation() {
        let route = ExploreAuthorProfileRoute(
            authorUserId: "author-1",
            authorName: "Chris",
            authorUsername: nil,
            authorAvatarUrl: nil
        )

        XCTAssertEqual(
            ExploreAuthorProfilePresentation.libraryNavigationTitle(
                route: route,
                currentUserId: "AUTHOR-1"
            ),
            "Your published scans"
        )
        XCTAssertEqual(
            ExploreAuthorProfilePresentation.libraryNavigationTitle(
                route: route,
                currentUserId: "viewer-1"
            ),
            "Chris’ scans"
        )
    }

    func testProBadgeUsesProjectedEntitlementExceptForCurrentViewerFallback() {
        let remoteProfile = ExploreAuthorProfileTestFixtures.profile(authorIsPro: false)
        let projectedProProfile = ExploreAuthorProfileTestFixtures.profile(authorIsPro: true)

        XCTAssertFalse(ExploreAuthorProfilePresentation.shouldShowProBadge(
            profile: remoteProfile,
            currentUserId: "viewer-1",
            currentUserIsSubscribed: true
        ))
        XCTAssertTrue(ExploreAuthorProfilePresentation.shouldShowProBadge(
            profile: remoteProfile,
            currentUserId: "author-1",
            currentUserIsSubscribed: true
        ))
        XCTAssertTrue(ExploreAuthorProfilePresentation.shouldShowProBadge(
            profile: projectedProProfile,
            currentUserId: "viewer-1",
            currentUserIsSubscribed: false
        ))
    }

    func testPostDeduplicationKeepsFirstOccurrenceOrder() {
        let first = ExploreAuthorProfileTestFixtures.post(id: "first")
        let duplicate = ExploreAuthorProfileTestFixtures.post(id: "first", sharedAt: "2026-07-01T00:00:00Z")
        let second = ExploreAuthorProfileTestFixtures.post(id: "second")

        XCTAssertEqual(
            ExploreAuthorProfilePresentation.deduplicatedPosts([first, duplicate, second]).map(\.id),
            ["first", "second"]
        )
    }
}
