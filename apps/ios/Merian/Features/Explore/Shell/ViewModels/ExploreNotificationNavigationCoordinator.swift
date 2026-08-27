@MainActor
final class ExploreNotificationNavigationCoordinator {
    private var openToken: ExploreNotificationOpenToken?
    private var stagedDestination: ExploreNotificationDismissalDestination?
    private var pendingDestination: ExploreNotificationDismissalDestination?

    func prepareDestination(
        for notification: ExploreNotification,
        fieldTripsEnabled: Bool,
        isSheetPresented: @MainActor () -> Bool,
        preparePostId: @MainActor (_ postId: String) async throws -> String
    ) async -> ExploreNotificationOpenOutcome {
        guard isSheetPresented() else { return .ignored }

        let token = ExploreNotificationOpenToken()
        openToken = token
        stagedDestination = nil
        pendingDestination = nil

        if notification.type == .mediaMissing {
            return stage(.scansLibrary, token: token, isSheetPresented: isSheetPresented)
        }

        if notification.type.isCommunityNotification,
           let requestId = notification.communityRequestId {
            return stage(
                .communityRequest(requestId),
                token: token,
                isSheetPresented: isSheetPresented
            )
        }

        if notification.type.isFieldTripNotification,
           let publicationId = notification.fieldTripPublicationId {
            guard fieldTripsEnabled else { return ignore(token) }
            return stage(
                .fieldTripPublication(publicationId),
                token: token,
                isSheetPresented: isSheetPresented
            )
        }

        guard let postId = notification.postId else { return ignore(token) }

        do {
            let preparedPostId = try await preparePostId(postId)
            guard isCurrent(token, isSheetPresented: isSheetPresented) else {
                return ignore(token)
            }

            let targetReplyParentCommentId = notification.parentCommentId
                ?? (notification.type == .commentReply ? notification.commentId : nil)
            let targetCommentId = targetReplyParentCommentId == notification.commentId
                ? nil
                : notification.commentId

            if notification.type == .commentReply,
               let targetReplyId = notification.commentId {
                return stage(
                    .post(
                        postId: preparedPostId,
                        focusCommentComposer: false,
                        targetCommentId: nil,
                        targetReplyParentCommentId: nil,
                        replyThreadTarget: ExploreNotificationReplyThreadTarget(
                            parentCommentId: notification.parentCommentId,
                            targetReplyId: targetReplyId,
                            fallbackReply: ExploreNotificationReplyFallback(
                                commentId: targetReplyId,
                                body: notification.commentBody,
                                authorUserId: notification.triggeringUserId,
                                authorName: notification.triggeringUserName,
                                createdAt: notification.createdAt
                            )
                        )
                    ),
                    token: token,
                    isSheetPresented: isSheetPresented
                )
            }

            return stage(
                .post(
                    postId: preparedPostId,
                    focusCommentComposer: notification.type == .comment && targetCommentId == nil,
                    targetCommentId: targetCommentId ?? targetReplyParentCommentId,
                    targetReplyParentCommentId: targetReplyParentCommentId,
                    replyThreadTarget: nil
                ),
                token: token,
                isSheetPresented: isSheetPresented
            )
        } catch {
            guard isCurrent(token, isSheetPresented: isSheetPresented) else {
                return ignore(token)
            }
            return .failed(token, error)
        }
    }

    func invalidateOpen() {
        openToken = nil
        stagedDestination = nil
    }

    func commitStagedDestination(
        _ token: ExploreNotificationOpenToken,
        isSheetPresented: @MainActor () -> Bool
    ) -> Bool {
        guard isCurrent(token, isSheetPresented: isSheetPresented),
              let stagedDestination else {
            return false
        }
        openToken = nil
        self.stagedDestination = nil
        pendingDestination = stagedDestination
        return true
    }

    func commitFailedOpen(
        _ token: ExploreNotificationOpenToken,
        isSheetPresented: @MainActor () -> Bool
    ) -> Bool {
        guard isCurrent(token, isSheetPresented: isSheetPresented) else {
            return false
        }
        openToken = nil
        stagedDestination = nil
        pendingDestination = nil
        return true
    }

    func takePendingDestination() -> ExploreNotificationDismissalDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    private func stage(
        _ destination: ExploreNotificationDismissalDestination,
        token: ExploreNotificationOpenToken,
        isSheetPresented: @MainActor () -> Bool
    ) -> ExploreNotificationOpenOutcome {
        guard isCurrent(token, isSheetPresented: isSheetPresented) else {
            return ignore(token)
        }
        stagedDestination = destination
        return .staged(token)
    }

    private func ignore(
        _ token: ExploreNotificationOpenToken
    ) -> ExploreNotificationOpenOutcome {
        guard openToken == token else { return .ignored }
        openToken = nil
        stagedDestination = nil
        return .ignored
    }

    private func isCurrent(
        _ token: ExploreNotificationOpenToken,
        isSheetPresented: @MainActor () -> Bool
    ) -> Bool {
        openToken == token && isSheetPresented()
    }
}
