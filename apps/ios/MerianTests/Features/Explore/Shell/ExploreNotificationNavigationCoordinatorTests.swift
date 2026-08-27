import Foundation
@testable import Merian
import Testing

@Suite("Explore notification navigation coordinator")
@MainActor
struct ExploreNotificationNavigationCoordinatorTests {
    @Test func mediaRecoveryStagesScansLibrary() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let outcome = await coordinator.prepareDestination(
            for: notification(id: "media", type: .mediaMissing, postId: nil),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )

        guard case .staged(let token) = outcome else {
            Issue.record("Expected media recovery to stage a destination")
            return
        }
        #expect(coordinator.commitStagedDestination(token, isSheetPresented: { true }))
        #expect(coordinator.takePendingDestination() == .scansLibrary)
        #expect(coordinator.takePendingDestination() == nil)
    }

    @Test func communityAndFieldTripDestinationsStayTyped() async {
        let coordinator = ExploreNotificationNavigationCoordinator()

        let communityOutcome = await coordinator.prepareDestination(
            for: notification(
                id: "community",
                type: .communityRequestResolved,
                postId: nil,
                communityRequestId: "request-id"
            ),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )
        guard case .staged(let communityToken) = communityOutcome else {
            Issue.record("Expected Community activity to stage a destination")
            return
        }
        #expect(
            coordinator.commitStagedDestination(
                communityToken,
                isSheetPresented: { true }
            )
        )
        #expect(
            coordinator.takePendingDestination() == .communityRequest("request-id")
        )

        let fieldTripOutcome = await coordinator.prepareDestination(
            for: notification(
                id: "field-trip",
                type: .fieldTripComment,
                postId: nil,
                fieldTripPublicationId: "publication-id"
            ),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )
        guard case .staged(let fieldTripToken) = fieldTripOutcome else {
            Issue.record("Expected Field-trip activity to stage a destination")
            return
        }
        #expect(
            coordinator.commitStagedDestination(
                fieldTripToken,
                isSheetPresented: { true }
            )
        )
        #expect(
            coordinator.takePendingDestination()
                == .fieldTripPublication("publication-id")
        )
    }

    @Test func disabledFieldTripsDoNotStageNavigation() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let outcome = await coordinator.prepareDestination(
            for: notification(
                id: "field-trip",
                type: .fieldTripReply,
                postId: nil,
                fieldTripPublicationId: "publication-id"
            ),
            fieldTripsEnabled: false,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )

        guard case .ignored = outcome else {
            Issue.record("Expected disabled Field-trip navigation to be ignored")
            return
        }
        #expect(coordinator.takePendingDestination() == nil)
    }

    @Test func replyNotificationPreservesSanitizedFallbackRoute() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let source = notification(
            id: "reply",
            type: .commentReply,
            postId: "post-id",
            commentId: "reply-id",
            parentCommentId: "parent-id",
            triggeringUserId: "author-id",
            triggeringUserName: "Avery Explorer",
            commentBody: "Fallback reply"
        )
        let outcome = await coordinator.prepareDestination(
            for: source,
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: { _ in "prepared-post-id" }
        )

        guard case .staged(let token) = outcome else {
            Issue.record("Expected reply activity to stage a destination")
            return
        }
        #expect(coordinator.commitStagedDestination(token, isSheetPresented: { true }))
        #expect(
            coordinator.takePendingDestination() == .post(
                postId: "prepared-post-id",
                focusCommentComposer: false,
                targetCommentId: nil,
                targetReplyParentCommentId: nil,
                replyThreadTarget: ExploreNotificationReplyThreadTarget(
                    parentCommentId: "parent-id",
                    targetReplyId: "reply-id",
                    fallbackReply: ExploreNotificationReplyFallback(
                        commentId: "reply-id",
                        body: "Fallback reply",
                        authorUserId: "author-id",
                        authorName: "Avery Explorer",
                        createdAt: source.createdAt
                    )
                )
            )
        )
    }

    @Test func newerSelectionFencesOlderPostPreparation() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let loader = DeferredPostIDLoader()

        let firstTask = Task { @MainActor in
            await coordinator.prepareDestination(
                for: notification(id: "first", postId: "post-1"),
                fieldTripsEnabled: true,
                isSheetPresented: { true },
                preparePostId: loader.load
            )
        }
        await loader.waitForRequest("post-1")

        let secondTask = Task { @MainActor in
            await coordinator.prepareDestination(
                for: notification(id: "second", postId: "post-2"),
                fieldTripsEnabled: true,
                isSheetPresented: { true },
                preparePostId: loader.load
            )
        }
        await loader.waitForRequest("post-2")

        loader.succeed("post-2", preparedId: "prepared-2")
        let secondOutcome = await secondTask.value
        loader.succeed("post-1", preparedId: "prepared-1")
        let firstOutcome = await firstTask.value

        guard case .staged(let secondToken) = secondOutcome else {
            Issue.record("Expected the latest selection to stage navigation")
            return
        }
        guard case .ignored = firstOutcome else {
            Issue.record("Expected stale post preparation to be ignored")
            return
        }
        #expect(
            coordinator.commitStagedDestination(
                secondToken,
                isSheetPresented: { true }
            )
        )
        #expect(
            coordinator.takePendingDestination() == .post(
                postId: "prepared-2",
                focusCommentComposer: false,
                targetCommentId: "comment-id",
                targetReplyParentCommentId: nil,
                replyThreadTarget: nil
            )
        )
    }

    @Test func newerPreparationInvalidatesAnUncommittedStagedDestination() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let loader = DeferredPostIDLoader()

        let firstOutcome = await coordinator.prepareDestination(
            for: notification(id: "first", type: .mediaMissing, postId: nil),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )
        guard case .staged(let firstToken) = firstOutcome else {
            Issue.record("Expected the first destination to be staged")
            return
        }

        let secondTask = Task { @MainActor in
            await coordinator.prepareDestination(
                for: notification(id: "second", postId: "post-2"),
                fieldTripsEnabled: true,
                isSheetPresented: { true },
                preparePostId: loader.load
            )
        }
        await loader.waitForRequest("post-2")

        #expect(
            !coordinator.commitStagedDestination(
                firstToken,
                isSheetPresented: { true }
            )
        )
        #expect(coordinator.takePendingDestination() == nil)

        loader.succeed("post-2", preparedId: "prepared-2")
        let secondOutcome = await secondTask.value
        guard case .staged(let secondToken) = secondOutcome else {
            Issue.record("Expected the newer destination to be staged")
            return
        }
        #expect(
            coordinator.commitStagedDestination(
                secondToken,
                isSheetPresented: { true }
            )
        )
        #expect(
            coordinator.takePendingDestination() == .post(
                postId: "prepared-2",
                focusCommentComposer: false,
                targetCommentId: "comment-id",
                targetReplyParentCommentId: nil,
                replyThreadTarget: nil
            )
        )
    }

    @Test func dismissalInvalidatesInFlightPreparation() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let loader = DeferredPostIDLoader()
        var isPresented = true

        let task = Task { @MainActor in
            await coordinator.prepareDestination(
                for: notification(id: "post", postId: "post-id"),
                fieldTripsEnabled: true,
                isSheetPresented: { isPresented },
                preparePostId: loader.load
            )
        }
        await loader.waitForRequest("post-id")

        isPresented = false
        coordinator.invalidateOpen()
        loader.succeed("post-id", preparedId: "prepared-id")
        let outcome = await task.value

        guard case .ignored = outcome else {
            Issue.record("Expected dismissal to invalidate post preparation")
            return
        }
        #expect(coordinator.takePendingDestination() == nil)
    }

    @Test func dismissalDiscardsAnUncommittedStagedDestination() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let outcome = await coordinator.prepareDestination(
            for: notification(id: "media", type: .mediaMissing, postId: nil),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )
        guard case .staged(let token) = outcome else {
            Issue.record("Expected media recovery to stage a destination")
            return
        }

        coordinator.invalidateOpen()

        #expect(
            !coordinator.commitStagedDestination(
                token,
                isSheetPresented: { false }
            )
        )
        #expect(coordinator.takePendingDestination() == nil)
    }

    @Test func currentPreparationFailureIsReturnedForFeedback() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let outcome = await coordinator.prepareDestination(
            for: notification(id: "post", postId: "post-id"),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: { _ in throw StubError.expected }
        )

        guard case .failed(let token, let error) = outcome else {
            Issue.record("Expected current preparation failure")
            return
        }
        #expect(coordinator.commitFailedOpen(token, isSheetPresented: { true }))
        #expect(error is StubError)
        #expect(coordinator.takePendingDestination() == nil)
    }

    @Test func newerOpenInvalidatesUncommittedFailureFeedback() async {
        let coordinator = ExploreNotificationNavigationCoordinator()
        let failedOutcome = await coordinator.prepareDestination(
            for: notification(id: "failed", postId: "post-id"),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: { _ in throw StubError.expected }
        )
        guard case .failed(let failedToken, _) = failedOutcome else {
            Issue.record("Expected the first open to fail")
            return
        }

        let stagedOutcome = await coordinator.prepareDestination(
            for: notification(id: "media", type: .mediaMissing, postId: nil),
            fieldTripsEnabled: true,
            isSheetPresented: { true },
            preparePostId: unexpectedPostLoader
        )
        guard case .staged(let stagedToken) = stagedOutcome else {
            Issue.record("Expected the newer destination to be staged")
            return
        }

        #expect(
            !coordinator.commitFailedOpen(
                failedToken,
                isSheetPresented: { true }
            )
        )
        #expect(
            coordinator.commitStagedDestination(
                stagedToken,
                isSheetPresented: { true }
            )
        )
        #expect(coordinator.takePendingDestination() == .scansLibrary)
    }

    private func notification(
        id: String,
        type: ExploreNotificationType = .comment,
        postId: String? = "post-id",
        communityRequestId: String? = nil,
        fieldTripPublicationId: String? = nil,
        commentId: String? = "comment-id",
        parentCommentId: String? = nil,
        triggeringUserId: String? = "author-id",
        triggeringUserName: String? = "Avery Explorer",
        commentBody: String? = "Field note"
    ) -> ExploreNotification {
        ExploreNotification(
            notificationId: id,
            postId: postId,
            communityRequestId: communityRequestId,
            fieldTripPublicationId: fieldTripPublicationId,
            type: type,
            commentId: commentId,
            parentCommentId: parentCommentId,
            reactionEmoji: nil,
            triggeringUserId: triggeringUserId,
            triggeringUserName: triggeringUserName,
            commentBody: commentBody,
            recentActorNames: [],
            actionCount: 1,
            isRead: false,
            isReplyToViewerComment: nil,
            communityTaxonCommonName: nil,
            communityTaxonScientificName: nil,
            communityRequestDisplayName: nil,
            createdAt: "2026-08-01T12:00:00Z",
            updatedAt: "2026-08-01T12:00:00Z"
        )
    }

    private func unexpectedPostLoader(_ postId: String) async throws -> String {
        Issue.record("Unexpected post preparation for \(postId)")
        throw StubError.unexpected
    }

    private enum StubError: Error {
        case expected
        case unexpected
    }
}

@MainActor
private final class DeferredPostIDLoader {
    private var continuations: [String: CheckedContinuation<String, Error>] = [:]

    func load(_ postId: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            continuations[postId] = continuation
        }
    }

    func waitForRequest(_ postId: String) async {
        while continuations[postId] == nil {
            await Task.yield()
        }
    }

    func succeed(_ postId: String, preparedId: String) {
        continuations.removeValue(forKey: postId)?.resume(returning: preparedId)
    }
}
