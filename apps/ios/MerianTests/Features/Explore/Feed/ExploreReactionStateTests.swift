import XCTest

@testable import Merian

@MainActor
final class ExploreReactionStateTests: XCTestCase {
    private func model(_ reactions: ExploreReactionDependencies) -> ExploreFeedViewModel {
        ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(reactions: reactions))
    }

    private func response(_ id: String, _ emoji: String, _ count: Int, _ selected: Bool) -> ExploreReactionResponse {
        .init(
            targetId: id, reaction: .init(emoji: emoji, count: count, viewerHasReacted: selected), likeCount: nil,
            viewerHasLiked: nil)
    }

    func testReactionResponsesDoNotDuplicateTapFeedbackButDirectLikesStillAcknowledge() async throws {
        var selections = 0
        let vm = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                selectionFeedback: { selections += 1 },
                reactions: .init(
                    set: { _, id, emoji, selected in self.response(id, emoji, selected ? 1 : 0, selected) },
                    load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected })))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let comment = ExploreFeedTestFixtures.comment(id: "comment")
        vm.upsertPost(post)
        vm.comments = [comment]

        await vm.setPostReaction(for: post, emoji: "😂", selected: true)
        await vm.setPostReaction(for: post, emoji: "😂", selected: false)
        _ = try await vm.performCommentReaction(for: comment, emoji: "❤️", selected: true)
        _ = try await vm.performCommentReaction(for: comment, emoji: "❤️", selected: false)
        await vm.setPostReaction(for: post, emoji: "❤️", selected: true)
        await vm.setPostReaction(for: post, emoji: "❤️", selected: true)
        XCTAssertEqual(selections, 0, "The shared picker/chip already acknowledged these taps.")

        await vm.toggleLike(for: post)
        XCTAssertEqual(selections, 1, "Direct heart buttons retain their existing feedback.")
    }

    func testFailedReactionsRetainErrorFeedbackWithoutSelectionConfirmation() async {
        var selections = 0
        var errors = 0
        let vm = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                setLike: { _, _ in throw ExploreFeedTestFixtures.StubError.failed },
                selectionFeedback: { selections += 1 },
                errorFeedback: { errors += 1 },
                reactions: .init(
                    set: { _, _, _, _ in throw ExploreFeedTestFixtures.StubError.failed },
                    load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected })))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let comment = ExploreFeedTestFixtures.comment(id: "comment")
        vm.upsertPost(post)
        vm.comments = [comment]
        await vm.setPostReaction(for: post, emoji: "😂", selected: true)
        do {
            _ = try await vm.performCommentReaction(for: comment, emoji: "❤️", selected: true)
            XCTFail("Expected failure")
        } catch {}
        await vm.setPostReaction(for: post, emoji: "❤️", selected: true)
        XCTAssertEqual(errors, 3)
        XCTAssertEqual(selections, 0)
    }

    func testCatalogContainsFlagsModifiersSequencesAndNames() {
        XCTAssertGreaterThan(ExploreEmojiCatalog.entries.count, 3000)
        for emoji in ["🇹🇷", "👍🏽", "👩🏽‍🔬", "❤️", "🫩"] {
            XCTAssertNotNil(ExploreEmojiCatalog.byEmoji[emoji])
            XCTAssertNotEqual(ExploreEmojiCatalog.name(for: emoji), emoji)
        }
        XCTAssertTrue(ExploreEmojiCatalog.byEmoji["❤️"]?.aliases.contains("❤") == true)
        XCTAssertNotEqual(ExploreEmojiCatalog.order(for: "👍"), ExploreEmojiCatalog.order(for: "👍🏽"))
    }

    func testPostReconcilesAuthoritativeCountAndMultipleSelections() async {
        let post = ExploreFeedTestFixtures.post(id: "post")
        let vm = model(
            .init(
                set: { _, id, emoji, selected in self.response(id, emoji, 7, selected) },
                load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        vm.upsertPost(post)
        await vm.setPostReaction(for: post, emoji: "😂", selected: true)
        await vm.setPostReaction(for: post, emoji: "👍🏽", selected: true)
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.count, 2)
        XCTAssertEqual(vm.store.post(id: post.id)?.reactions?.first?.count, 7)
        XCTAssertTrue(vm.post(id: post.id)?.reactions?.allSatisfy(\.viewerHasReacted) == true)
    }

    func testFailureRollsBackPostAndCommentAndReportsError() async {
        let vm = model(
            .init(
                set: { _, _, _, _ in throw ExploreFeedTestFixtures.StubError.failed },
                load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        vm.upsertPost(post)
        await vm.setPostReaction(for: post, emoji: "😂", selected: true)
        XCTAssertTrue(vm.post(id: post.id)?.reactions?.isEmpty == true)
        XCTAssertEqual(vm.toastMessage?.severity, .error)
        let comment = ExploreFeedTestFixtures.comment(id: "comment")
        vm.comments = [comment]
        do {
            _ = try await vm.performCommentReaction(for: comment, emoji: "❤️", selected: true)
            XCTFail("Expected failure")
        } catch {}
        XCTAssertEqual(vm.comments[0].reactions, comment.reactions)
    }

    func testQueuedDifferentEmojisRemainSelectedAndRemoveIndependently() async {
        let started = expectation(description: "first reaction starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        var calls: [String] = []
        let vm = model(.init(
            set: { _, id, emoji, selected in
                calls.append(emoji)
                if calls.count == 1 {
                    return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
                }
                return self.response(id, emoji, selected ? 1 : 0, selected)
            }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        var post = ExploreFeedTestFixtures.post(id: "post")
        post.reactions = []
        vm.upsertPost(post)
        let first = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        let second = Task { await vm.setPostReaction(for: post, emoji: "👍🏽", selected: true) }
        await Task.yield()
        XCTAssertEqual(calls, ["😂"])
        pending?.resume(returning: response(post.id, "😂", 1, true))
        await first.value
        await second.value
        XCTAssertEqual(calls, ["😂", "👍🏽"])
        XCTAssertEqual(Set(vm.post(id: post.id)?.reactions?.map(\.emoji) ?? []), ["😂", "👍🏽"])
        XCTAssertTrue(vm.post(id: post.id)?.reactions?.allSatisfy(\.viewerHasReacted) == true)

        await vm.setPostReaction(for: post, emoji: "😂", selected: false)
        XCTAssertEqual(vm.post(id: post.id)?.reactions, [
            .init(emoji: "👍🏽", count: 1, viewerHasReacted: true)
        ])
    }

    func testUnavailableRouteRollsBackQueuedEmojisWithoutRemovingExistingReactionOrLike() async {
        let started = expectation(description: "unavailable reaction route starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        var calls = 0
        let vm = model(.init(
            set: { _, _, _, _ in
                calls += 1
                if calls == 1 {
                    return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
                }
                throw MerianError.edgeFunctionUnavailable
            }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        var post = ExploreFeedTestFixtures.post(id: "post")
        post.reactions = [.init(emoji: "🎉", count: 2, viewerHasReacted: true)]
        post.viewerHasLiked = true
        post.likeCount = 3
        vm.upsertPost(post)
        let first = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.first { $0.emoji == "😂" }?.viewerHasReacted, true)
        let second = Task { await vm.setPostReaction(for: post, emoji: "👍🏽", selected: true) }
        await Task.yield()
        pending?.resume(throwing: MerianError.edgeFunctionUnavailable)
        await first.value
        await second.value
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(vm.post(id: post.id)?.reactions, post.reactions)
        XCTAssertEqual(vm.post(id: post.id)?.viewerHasLiked, true)
        XCTAssertEqual(vm.post(id: post.id)?.likeCount, 3)
        XCTAssertEqual(vm.toastMessage?.severity, .error)
    }

    func testRefreshInvalidatesPendingPostResponse() async {
        let started = expectation(description: "mutation started")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        let vm = model(
            .init(
                set: { _, _, _, _ in
                    try await withCheckedThrowingContinuation {
                        pending = $0
                        started.fulfill()
                    }
                }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        vm.upsertPost(post)
        let task = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        vm.activeFeedRequestId = UUID()
        var refreshed = post
        refreshed.reactions = [.init(emoji: "😂", count: 9, viewerHasReacted: false)]
        vm.upsertPost(refreshed)
        pending?.resume(returning: response(post.id, "😂", 1, true))
        await task.value
        XCTAssertEqual(vm.post(id: post.id)?.reactions, refreshed.reactions)
    }

    func testMutationsAreSerializedAndRemovalUsesLatestState() async {
        let started = expectation(description: "first started")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        var calls = 0
        let vm = model(
            .init(
                set: { _, id, emoji, selected in
                    calls += 1
                    if calls == 1 {
                        return try await withCheckedThrowingContinuation {
                            pending = $0
                            started.fulfill()
                        }
                    }
                    return self.response(id, emoji, 0, selected)
                }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let first = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        let second = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: false) }
        await Task.yield()
        XCTAssertEqual(calls, 1)
        pending?.resume(returning: response(post.id, "😂", 1, true))
        await first.value
        await second.value
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(vm.post(id: post.id)?.reactions?.isEmpty == true)
    }

    func testPaginationMergesEmojiIdentityAndRetainsOutOfPageSelection() async {
        var post = ExploreFeedTestFixtures.post(id: "post")
        post.reactions = [
            .init(emoji: "😂", count: 1, viewerHasReacted: false), .init(emoji: "🇹🇷", count: 1, viewerHasReacted: true),
        ]
        post.reactionsNextCursor = 12
        let vm = model(
            .init(
                set: { _, _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected },
                load: { _, _, cursor in
                    XCTAssertEqual(cursor, 12)
                    return .init(
                        reactions: [
                            .init(emoji: "😂", count: 2, viewerHasReacted: false),
                            .init(emoji: "👍🏽", count: 3, viewerHasReacted: false),
                        ], reactionsNextCursor: nil)
                }))
        vm.upsertPost(post)
        await vm.loadMorePostReactions(for: post)
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.count, 3)
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.first { $0.emoji == "😂" }?.count, 2)
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.first { $0.emoji == "🇹🇷" }?.viewerHasReacted, true)
        XCTAssertNil(vm.post(id: post.id)?.reactionsNextCursor)
    }

    func testCommentRefreshRejectsLateReactionResult() async {
        let started = expectation(description: "comment mutation starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        let vm = model(
            .init(
                set: { _, _, _, _ in
                    try await withCheckedThrowingContinuation {
                        pending = $0
                        started.fulfill()
                    }
                }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let comment = ExploreFeedTestFixtures.comment(id: "comment")
        vm.comments = [comment]
        let task = Task { try await vm.performCommentReaction(for: comment, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        vm.activeCommentsRequestId = UUID()
        vm.comments = [comment]
        pending?.resume(returning: response(comment.id, "😂", 1, true))
        do {
            _ = try await task.value
            XCTFail("A replaced thread must discard the old response")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(vm.comments[0].reactions, comment.reactions)
    }

    func testAccountChangeRejectsLateReactionResponse() async {
        let started = expectation(description: "reaction starts")
        var viewer = "first-viewer"
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        let vm = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                currentViewer: { .init(userID: viewer, avatarURL: nil) },
                reactions: .init(
                    set: { _, _, _, _ in
                        try await withCheckedThrowingContinuation {
                            pending = $0
                            started.fulfill()
                        }
                    }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected })
            ))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let task = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        viewer = "second-viewer"
        var otherViewerPost = post
        otherViewerPost.reactions = [.init(emoji: "😂", count: 1, viewerHasReacted: false)]
        vm.upsertPost(otherViewerPost)
        pending?.resume(returning: response(post.id, "😂", 1, true))
        await task.value
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.first?.viewerHasReacted, false)
    }

    func testQueuedHeartSelectionsStaySelected() async {
        let started = expectation(description: "emoji mutation starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        let vm = model(
            .init(
                set: { _, _, _, _ in
                    try await withCheckedThrowingContinuation {
                        pending = $0
                        started.fulfill()
                    }
                }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let emoji = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        let firstHeart = Task { await vm.setPostReaction(for: post, emoji: "❤️", selected: true) }
        let secondHeart = Task { await vm.setPostReaction(for: post, emoji: "❤️", selected: true) }
        await Task.yield()
        pending?.resume(returning: response(post.id, "😂", 1, true))
        await emoji.value
        await firstHeart.value
        await secondHeart.value
        XCTAssertEqual(vm.post(id: post.id)?.viewerHasLiked, true)
        XCTAssertEqual(vm.post(id: post.id)?.likeCount, 1)
    }

    func testOlderPagePreservesReactionsChangedAfterItsRequestStarted() async {
        let post = ExploreFeedTestFixtures.post(id: "post")
        let vm = model(
            .init(
                set: { _, id, emoji, selected in self.response(id, emoji, 4, selected) },
                load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        vm.upsertPost(post)
        let beforePage = vm.reactionRevisions
        await vm.setPostReaction(for: post, emoji: "😂", selected: true)
        let merged = vm.preservingNewerReactions(in: [post], since: beforePage)
        XCTAssertEqual(merged[0].reactions?.first?.count, 4)
        XCTAssertEqual(merged[0].reactions?.first?.viewerHasReacted, true)
    }

    func testPostRedHeartUsesExistingLikeAndNeverAddsChip() async {
        let vm = model(.unavailable)
        let post = ExploreFeedTestFixtures.post(id: "post")
        vm.upsertPost(post)
        await vm.setPostReaction(for: post, emoji: "❤️", selected: true)
        await vm.setPostReaction(for: post, emoji: "❤️", selected: true)
        XCTAssertEqual(vm.post(id: post.id)?.likeCount, 1)
        XCTAssertEqual(vm.post(id: post.id)?.viewerHasLiked, true)
        XCTAssertNil(vm.post(id: post.id)?.reactions)
    }
    func testDetailRefreshUpdatesSharedSummaryAndCursor() async {
        let vm = model(.unavailable)
        let post = ExploreFeedTestFixtures.post(id: "post")
        vm.upsertPost(post)
        var detail = ExploreFeedTestFixtures.detail(postId: post.id)
        detail.reactions = [.init(emoji: "😂", count: 8, viewerHasReacted: false)]
        detail.reactionsNextCursor = 12
        await vm.loadPostDetailReactions(postId: post.id) { detail }
        XCTAssertEqual(vm.post(id: post.id)?.reactions, detail.reactions)
        XCTAssertEqual(vm.post(id: post.id)?.reactionsNextCursor, 12)
    }

    func testDetailResponseCannotOverwriteReactionAddedDuringLoad() async {
        let started = expectation(description: "detail starts")
        var pending: CheckedContinuation<ExplorePostDetail?, Never>?
        let vm = model(.init(
            set: { _, id, emoji, selected in self.response(id, emoji, 4, selected) },
            load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        vm.upsertPost(post)
        let load = Task {
            await vm.loadPostDetailReactions(postId: post.id) {
                await withCheckedContinuation { pending = $0; started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 1)
        await vm.setPostReaction(for: post, emoji: "😂", selected: true)
        var stale = ExploreFeedTestFixtures.detail(postId: post.id)
        stale.reactions = []
        pending?.resume(returning: stale)
        await load.value
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.first?.count, 4)
    }

    func testQueuedReactionsDoNotRestoreRemovedPost() async {
        let started = expectation(description: "mutation starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        var calls = 0
        let vm = model(.init(
            set: { _, _, _, _ in
                calls += 1
                return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
            }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let first = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        let queued = Task { await vm.setPostReaction(for: post, emoji: "👍", selected: true) }
        let heart = Task { await vm.setPostReaction(for: post, emoji: "❤️", selected: true) }
        await Task.yield()
        vm.removePost(id: post.id)
        pending?.resume(returning: response(post.id, "😂", 1, true))
        await first.value
        await queued.value
        await heart.value
        XCTAssertEqual(calls, 1)
        XCTAssertNil(vm.post(id: post.id))
    }

    func testPageStartedDuringMutationPreservesPendingAndSettledState() async {
        let started = expectation(description: "mutation starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        let vm = model(.init(
            set: { _, _, _, _ in
                try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
            }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let mutation = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        let snapshot = vm.reactionRevisions
        XCTAssertEqual(vm.preservingNewerReactions(in: [post], since: snapshot)[0].reactions?.first?.count, 1)
        pending?.resume(returning: response(post.id, "😂", 5, true))
        await mutation.value
        XCTAssertEqual(vm.preservingNewerReactions(in: [post], since: snapshot)[0].reactions?.first?.count, 5)
    }

    func testReplyExpansionPreservesReactionChangedAfterReadStarts() async {
        let started = expectation(description: "reply read starts")
        var pending: CheckedContinuation<[ExploreComment], Error>?
        let parent = ExploreFeedTestFixtures.comment(id: "parent")
        let reply = ExploreFeedTestFixtures.comment(id: "reply", parentCommentId: parent.id)
        let vm = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                loadReplies: { _, _, _, _ in
                    try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
                }, reactions: .init(
                    set: { _, id, emoji, selected in self.response(id, emoji, 6, selected) },
                    load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected })))
        vm.comments = [parent]
        vm.repliesByCommentId[parent.id] = [reply]
        let read = Task { await vm.loadReplies(for: parent) }
        await fulfillment(of: [started], timeout: 1)
        do { _ = try await vm.performCommentReaction(for: reply, emoji: "😂", selected: true) }
        catch { XCTFail("Unexpected reaction failure") }
        pending?.resume(returning: [reply])
        await read.value
        XCTAssertEqual(vm.repliesByCommentId[parent.id]?.first?.reactions?.first?.count, 6)
        XCTAssertEqual(vm.repliesByCommentId[parent.id]?.first?.reactions?.first?.viewerHasReacted, true)
    }

    func testCancelledViewTaskStillReconcilesSuccessfulMutation() async {
        let started = expectation(description: "mutation starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        let vm = model(.init(
            set: { _, _, _, _ in
                try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
            }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected }))
        let post = ExploreFeedTestFixtures.post(id: "post")
        let mutation = Task { await vm.setPostReaction(for: post, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        mutation.cancel()
        pending?.resume(returning: response(post.id, "😂", 5, true))
        await mutation.value
        XCTAssertEqual(vm.post(id: post.id)?.reactions?.first?.count, 5)
    }

    func testPostRefreshWaitsForPendingMutationBeforeReading() async {
        let started = expectation(description: "mutation starts")
        var pending: CheckedContinuation<ExploreReactionResponse, Error>?
        var readCount = 0
        var serverPost = ExploreFeedTestFixtures.post(id: "post")
        serverPost.reactions = []
        let vm = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                loadPost: { _ in readCount += 1; return serverPost },
                reactions: .init(
                    set: { _, _, _, _ in
                        try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
                    }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected })))
        vm.upsertPost(serverPost)
        let mutation = Task { await vm.setPostReaction(for: serverPost, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        let refresh = Task { await vm.refreshPost(postId: serverPost.id) }
        await Task.yield()
        XCTAssertEqual(readCount, 0)
        serverPost.reactions = [.init(emoji: "😂", count: 4, viewerHasReacted: true)]
        pending?.resume(returning: response(serverPost.id, "😂", 4, true))
        await mutation.value
        await refresh.value
        XCTAssertEqual(readCount, 1)
        XCTAssertEqual(vm.post(id: serverPost.id)?.reactions, serverPost.reactions)
    }

    func testLightweightMapPostHydratesBeforeReactionWrite() async {
        let started = expectation(description: "map hydration starts")
        var pending: CheckedContinuation<ExplorePost, Error>?
        var mutationCount = 0
        var hydrated = ExploreFeedTestFixtures.post(id: "map-post")
        hydrated.reactions = [.init(emoji: "👍", count: 3, viewerHasReacted: false)]
        let vm = ExploreFeedViewModel(
            appSettings: ExploreFeedTestFixtures.appSettings(),
            dependencies: ExploreFeedTestFixtures.dependencies(
                loadPost: { _ in
                    try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
                }, reactions: .init(
                    set: { _, id, emoji, selected in
                        mutationCount += 1
                        return self.response(id, emoji, 2, selected)
                    }, load: { _, _, _ in throw ExploreFeedTestFixtures.StubError.unexpected })))
        let marker = ExploreFeedTestFixtures.post(id: "map-post")
        vm.upsertPost(marker)
        let mutation = Task { await vm.setPostReaction(for: marker, emoji: "😂", selected: true) }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(mutationCount, 0)
        pending?.resume(returning: hydrated)
        await mutation.value
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(vm.post(id: marker.id)?.reactions?.count, 2)
        XCTAssertEqual(vm.post(id: marker.id)?.reactions?.first { $0.emoji == "👍" }?.count, 3)
    }

    func testOlderPageCannotRestoreLocallyRemovedPost() {
        let vm = model(.unavailable)
        let post = ExploreFeedTestFixtures.post(id: "post")
        vm.upsertPost(post)
        let snapshot = vm.reactionRevisions
        vm.removePost(id: post.id)
        XCTAssertTrue(vm.preservingNewerReactions(in: [post], since: snapshot).isEmpty)
    }

}
