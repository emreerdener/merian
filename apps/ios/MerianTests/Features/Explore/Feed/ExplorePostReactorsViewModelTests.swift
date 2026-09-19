import XCTest

@testable import Merian

@MainActor
final class ExplorePostReactorsViewModelTests: XCTestCase {
    private func person(_ id: String, emojis: [String] = ["❤️", "😂"]) -> ExplorePostReactor {
        .init(userId: id, displayName: id, username: nil, avatarUrl: nil, emojis: emojis)
    }
    private func page(_ ids: [String], total: Int? = nil, cursor: String? = nil) -> ExplorePostReactorsPage {
        .init(totalCount: total ?? ids.count, previewNames: Array(ids.prefix(2)), reactors: ids.map { person($0) }, nextCursor: cursor)
    }

    func testReactorDecodesPublicUsernameAndPrefersItForPresentation() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reactor = try decoder.decode(ExplorePostReactor.self, from: Data(#"""
        {"user_id":"fixture-user","display_name":"Observer A.","username":"nature_observer","avatar_url":null,"emojis":["😂"]}
        """#.utf8))
        XCTAssertEqual(reactor.username, "nature_observer")
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(
            from: reactor.displayName, username: reactor.username, preferUsername: true
        ), "@nature_observer")
    }

    func testReactorStillDecodesResponseBeforeUsernameRollout() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reactor = try decoder.decode(ExplorePostReactor.self, from: Data(#"""
        {"user_id":"fixture-user","display_name":"Observer","avatar_url":null,"emojis":["😂"]}
        """#.utf8))
        XCTAssertNil(reactor.username)
        XCTAssertEqual(ExplorePost.publicAuthorDisplayName(
            from: reactor.displayName, username: reactor.username, preferUsername: true
        ), "Observer")
    }

    func testSummaryCountsPeopleRatherThanEmojiAndHandlesGrammar() async {
        var count = 0
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, _ in
            self.page(Array(["Alex", "Bea"].prefix(count)), total: count)
        }, currentViewer: { "viewer" })
        await model.refresh()
        XCTAssertNil(model.summary)
        for (total, expected) in [(1, "Alex reacted"), (2, "Alex and Bea reacted"),
                                  (3, "Alex, Bea, and 1 other reacted"), (6, "Alex, Bea, and 4 others reacted")] {
            count = total
            await model.refresh()
            XCTAssertEqual(model.summary, expected)
        }
    }

    func testPaginationMergesPeopleByIdentityAndKeepsAllTheirEmoji() async {
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, cursor in
            cursor == nil ? self.page(["Alex", "Bea"], total: 3, cursor: "Bea") : self.page(["Bea", "Cam"], total: 3)
        }, currentViewer: { "viewer" })
        await model.refresh()
        await model.loadMore()
        XCTAssertEqual(model.reactors.map(\.id), ["Alex", "Bea", "Cam"])
        XCTAssertEqual(model.reactors.first?.emojis, ["❤️", "😂"])
        XCTAssertNil(model.nextCursor)
    }

    func testRefreshDiscardsLatePageAndInvalidationDiscardsLateRefresh() async {
        let started = expectation(description: "page started")
        var continuation: CheckedContinuation<ExplorePostReactorsPage, Error>?
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, cursor in
            if cursor == nil { return self.page(["Alex"], total: 2, cursor: "Alex") }
            return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }, currentViewer: { "viewer" })
        await model.refresh()
        let task = Task { await model.loadMore() }
        await fulfillment(of: [started], timeout: 1)
        await model.refresh()
        continuation?.resume(returning: page(["Old person"]))
        await task.value
        XCTAssertEqual(model.reactors.map(\.id), ["Alex"])

        let pending = expectation(description: "refresh started")
        let other = ExplorePostReactorsViewModel(postId: "post", load: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; pending.fulfill() }
        }, currentViewer: { "viewer" })
        let refresh = Task { await other.refresh() }
        await fulfillment(of: [pending], timeout: 1)
        other.invalidate()
        continuation?.resume(returning: page(["Old person"]))
        await refresh.value
        XCTAssertTrue(other.reactors.isEmpty)
        XCTAssertNil(other.summary)
    }

    func testAccountChangeDiscardsLateResponse() async {
        var viewer = "one"
        let started = expectation(description: "started")
        var continuation: CheckedContinuation<ExplorePostReactorsPage, Error>?
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }, currentViewer: { viewer })
        let task = Task { await model.refresh() }
        await fulfillment(of: [started], timeout: 1)
        viewer = "two"
        continuation?.resume(returning: page(["Private to old viewer"]))
        await task.value
        XCTAssertTrue(model.reactors.isEmpty)
        XCTAssertFalse(model.hasLoaded)
    }

    func testFailureIsVisibleAndExplicitRetryRecovers() async {
        var fails = true
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, _ in
            if fails { throw URLError(.notConnectedToInternet) }
            return self.page(["Alex"])
        }, currentViewer: { "viewer" })
        await model.refresh()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        fails = false
        await model.refresh()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.summary, "Alex reacted")
    }
    func testPageFailurePreservesPeopleAndRetryUsesSameCursor() async {
        var attempts = 0
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, cursor in
            guard let cursor else { return self.page(["Alex"], total: 2, cursor: "Alex") }
            XCTAssertEqual(cursor, "Alex")
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return .init(totalCount: 2, previewNames: ["Alex", "Bea"], reactors: [self.person("Bea")], nextCursor: nil)
        }, currentViewer: { "viewer" })
        await model.refresh()
        await model.loadMore()
        XCTAssertEqual(model.reactors.map(\.id), ["Alex"])
        XCTAssertEqual(model.nextCursor, "Alex")
        XCTAssertNotNil(model.errorMessage)
        await model.loadMore()
        XCTAssertEqual(model.reactors.map(\.id), ["Alex", "Bea"])
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.nextCursor)
    }

    func testDuplicateLoadMoreIsSingleFlight() async {
        let started = expectation(description: "page started")
        var continuation: CheckedContinuation<ExplorePostReactorsPage, Error>?
        var calls = 0
        let model = ExplorePostReactorsViewModel(postId: "post", load: { _, cursor in
            guard cursor != nil else { return self.page(["Alex"], total: 2, cursor: "Alex") }
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        }, currentViewer: { "viewer" })
        await model.refresh()
        let task = Task { await model.loadMore() }
        await fulfillment(of: [started], timeout: 1)
        await model.loadMore()
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: page(["Bea"], total: 2))
        await task.value
        XCTAssertFalse(model.isLoadingMore)
    }

}
