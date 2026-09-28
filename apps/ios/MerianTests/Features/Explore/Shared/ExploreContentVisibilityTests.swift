import Foundation
@testable import Merian
import Testing

@Suite("Reported content visibility")
@MainActor
struct ExploreContentVisibilityTests {
    @Test func sharedStoresRejectLateHydrationAndPagination() {
        let visibility = ExploreContentVisibilityStore()
        let viewer = UUID()
        visibility.activate(viewerID: viewer)
        let feed = ExplorePostStore(visibility: visibility)
        let dictionary = ExplorePostStore(visibility: visibility)
        let post = ExploreFeedTestFixtures.post(id: "reported")
        feed.setFeedPosts([post])
        dictionary.upsert(post)
        #expect(visibility.hide(postID: post.id, for: viewer))
        feed.setFeedPosts([post])
        feed.appendUniqueFeedPosts([post])
        dictionary.upsert(post, includeInFeed: true)
        #expect(feed.feedPosts.isEmpty)
        #expect(dictionary.post(id: post.id) == nil)
        #expect(dictionary.allPosts.isEmpty)
    }

    @Test func accountSwitchRejectsOldReportCompletion() {
        let visibility = ExploreContentVisibilityStore()
        let first = UUID(), second = UUID()
        visibility.activate(viewerID: first)
        visibility.hide(postID: "old", for: first)
        let context = visibility.context
        visibility.activate(viewerID: second)
        #expect(visibility.context != context)
        #expect(!visibility.hide(postID: "late", for: first))
        #expect(visibility.isVisible(postID: "old"))
        #expect(visibility.isVisible(postID: "late"))
    }

    @Test func missingAccountCannotHideContent() {
        let visibility = ExploreContentVisibilityStore()
        #expect(!visibility.hide(postID: "post", for: nil))
        #expect(visibility.isVisible(postID: "post"))
    }

    @Test func duplicateReportDoesNotInvalidateAgain() {
        let visibility = ExploreContentVisibilityStore()
        let viewer = UUID()
        visibility.activate(viewerID: viewer)
        visibility.hide(postID: "UPPER", for: viewer)
        let context = visibility.context
        #expect(!visibility.hide(postID: "upper", for: viewer))
        #expect(visibility.context == context)
        #expect(!visibility.isVisible(postID: "UpPeR"))
    }
    @Test func confirmedReportsHideAcrossStoresAndFailuresKeepContent() async {
        let visibility = ExploreContentVisibilityStore()
        let viewer = UUID()
        visibility.activate(viewerID: viewer)
        let post = ExploreFeedTestFixtures.post(id: "report-success")
        let secondary = ExplorePostStore(visibility: visibility)
        secondary.upsert(post)
        let success = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                currentViewer: { .init(userID: viewer.uuidString, avatarURL: nil) },
                visibility: visibility, reportPost: { _ in }
            )
        )
        #expect(await success.report(post))
        #expect(secondary.post(id: post.id) == nil)
        let failure = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                currentViewer: { .init(userID: viewer.uuidString, avatarURL: nil) },
                visibility: visibility
            )
        )
        let failedPost = ExploreFeedTestFixtures.post(id: "report-failure")
        #expect(!(await failure.report(failedPost)))
        #expect(visibility.isVisible(postID: failedPost.id))
    }

    @Test func reportCompletionAfterSwitchAwayAndBackCannotHideCurrentSession() async {
        let visibility = ExploreContentVisibilityStore()
        let viewer = UUID()
        visibility.activate(viewerID: viewer)
        let post = ExploreFeedTestFixtures.post(id: "late-report")
        let model = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                currentViewer: { .init(userID: viewer.uuidString, avatarURL: nil) },
                visibility: visibility,
                reportPost: { _ in
                    visibility.activate(viewerID: UUID())
                    visibility.activate(viewerID: viewer)
                }
            )
        )
        #expect(!(await model.report(post)))
        #expect(visibility.isVisible(postID: post.id))
    }

    @Test func widgetGateRejectsLateWritesAfterReportAccountSwitchOrNewerWrite() {
        let visibility = ExploreContentVisibilityStore()
        let viewer = UUID()
        visibility.activate(viewerID: viewer)
        let gate = ExploreWidgetWriteGate()
        let first = gate.begin(visibility: visibility.context)
        #expect(gate.accepts(first, visibility: visibility.context))
        visibility.hide(postID: "reported", for: viewer)
        #expect(!gate.accepts(first, visibility: visibility.context))
        let afterReport = gate.begin(visibility: visibility.context)
        let newer = gate.begin(visibility: visibility.context)
        #expect(!gate.accepts(afterReport, visibility: visibility.context))
        #expect(gate.accepts(newer, visibility: visibility.context))
        visibility.activate(viewerID: UUID())
        visibility.activate(viewerID: viewer)
        #expect(!gate.accepts(newer, visibility: visibility.context))
        let active = gate.begin(visibility: visibility.context)
        gate.invalidate()
        #expect(!gate.accepts(active, visibility: visibility.context))
    }

}
