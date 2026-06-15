import SwiftUI

struct ExploreNotificationsSheet: View {
    let onUnreadNotificationsCleared: () -> Void
    let onOpenNotification: (ExploreNotification) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ExploreNotificationsViewModel()
    @State private var selectedNotificationId: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    loadingState
                } else if let errorMessage = viewModel.errorMessage, viewModel.notifications.isEmpty {
                    errorState(message: errorMessage)
                } else if viewModel.notifications.isEmpty {
                    emptyState
                } else {
                    notificationsScrollView
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                if !viewModel.notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                Task { await viewModel.markAllAsRead() }
                            } label: {
                                Label("Mark all as read", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
        .task {
            await fetchNotifications()
        }
    }

    private var notificationsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.notifications) { notification in
                    NotificationRowView(
                        notification: notification,
                        isRecentlyRead: viewModel.recentlyReadNotificationIds.contains(notification.id),
                        isLoading: selectedNotificationId == notification.id,
                        action: {
                            Task { await openNotification(notification) }
                        }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentNotification: notification) }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            await fetchNotifications(force: true)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading notifications...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "bell.slash",
            title: "Nothing new yet",
            message: "Follows, likes on your posts, comments on your posts, and reactions to your comments will show up here."
        )
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "exclamationmark.triangle",
            title: "Couldn’t load notifications",
            message: message
        ) {
            Button {
                Task { await fetchNotifications(force: true) }
            } label: {
                Text("Try again")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func fetchNotifications(force: Bool = false) async {
        let didClearUnread = await viewModel.fetchNotifications(force: force)
        if didClearUnread {
            onUnreadNotificationsCleared()
        }
    }

    private func openNotification(_ notification: ExploreNotification) async {
        guard notification.postId != nil else { return }
        guard selectedNotificationId == nil else { return }

        selectedNotificationId = notification.id
        defer { selectedNotificationId = nil }
        await onOpenNotification(notification)
    }
}

struct ExploreNotificationReplyThreadRoute: Identifiable, Equatable {
    let post: ExplorePost
    let parentCommentId: String?
    let targetReplyId: String
    let fallbackReply: ExploreNotificationReplyFallback

    var id: String {
        "\(post.id)-\(parentCommentId ?? "unknown-parent")-\(targetReplyId)"
    }

    init(
        post: ExplorePost,
        parentCommentId: String?,
        targetReplyId: String,
        fallbackReply: ExploreNotificationReplyFallback
    ) {
        self.post = post
        self.parentCommentId = parentCommentId
        self.targetReplyId = targetReplyId
        self.fallbackReply = fallbackReply
    }
}

struct ExploreNotificationReplyFallback: Hashable {
    let commentId: String
    let body: String?
    let authorUserId: String?
    let authorName: String?
    let createdAt: String
}

struct ExploreNotificationReplyThreadSheet: View {
    let route: ExploreNotificationReplyThreadRoute

    @Environment(\.dismiss) private var dismiss

    @State private var parentComment: ExploreComment?
    @State private var replies: [ExploreComment] = []
    @State private var isLoading = true
    @State private var isLoadingMoreReplies = false
    @State private var hasReachedEndOfReplies = true
    @State private var nextReplyCursor: ExploreCommentCursor?
    @State private var errorMessage: String?

    private let commentsPageSize = 100
    private let repliesPageSize = 100

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingState
                } else if let errorMessage {
                    errorState(message: errorMessage)
                } else if parentComment != nil || !replies.isEmpty {
                    threadContent(parentComment: parentComment)
                } else {
                    errorState(message: "This reply is no longer available.")
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Comment replies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .task(id: route.id) {
            await loadThread()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading reply...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        EmptyStateView(
            iconName: "bubble.left.and.exclamationmark.bubble.right",
            title: "Couldn’t open reply",
            message: message
        ) {
            Button {
                Task { await loadThread() }
            } label: {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func threadContent(parentComment: ExploreComment?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let parentComment {
                    originalComment(parentComment)
                }

                if replies.isEmpty {
                    Text("No replies were found for this thread.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 48)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(replies) { reply in
                            commentCard(reply)
                        }

                        if isLoadingMoreReplies {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .padding(.leading, 48)
                                .padding(.vertical, 8)
                        } else if !hasReachedEndOfReplies {
                            Button {
                                Task { await loadMoreReplies() }
                            } label: {
                                Text("Load more replies")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable {
            await loadThread()
        }
    }

    private func originalComment(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            commentHeader(comment)

            Text(comment.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentCard(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            commentHeader(comment)

            Text(comment.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func commentHeader(_ comment: ExploreComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            authorAvatarView(for: comment)

            VStack(alignment: .leading, spacing: 3) {
                Text(comment.displayAuthorName)
                    .font(.subheadline.weight(.semibold))

                if let createdAtText = createdAtText(for: comment) {
                    Text(createdAtText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func authorAvatarView(for comment: ExploreComment) -> some View {
        if let avatarUrl = resolvedAuthorAvatarUrl(for: comment) {
            AsyncImage(url: avatarUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackAuthorAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAuthorAvatar
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            fallbackAuthorAvatar
        }
    }

    private var fallbackAuthorAvatar: some View {
        Image(systemName: "person.crop.circle")
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(.primary)
    }

    private func resolvedAuthorAvatarUrl(for comment: ExploreComment) -> URL? {
        if let avatarUrlString = comment.authorAvatarUrl,
           let avatarUrl = URL(string: avatarUrlString) {
            return avatarUrl
        }

        let currentUserId = SupabaseManager.shared.currentUser?.id.uuidString
        if currentUserId?.lowercased() == comment.authorUserId.lowercased() {
            return SupabaseManager.shared.currentUserAvatarUrl
        }

        if route.post.authorUserId.lowercased() == comment.authorUserId.lowercased(),
           let postAvatarUrlString = route.post.authorAvatarUrl,
           let postAvatarUrl = URL(string: postAvatarUrlString) {
            return postAvatarUrl
        }

        return nil
    }

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
    }

    @MainActor
    private func loadThread() async {
        isLoading = true
        errorMessage = nil
        parentComment = nil
        replies = []
        hasReachedEndOfReplies = true
        nextReplyCursor = nil

        do {
            async let parentTask = loadParentCommentIfPossible()
            async let repliesTask = loadRepliesThroughTarget()
            let (loadedParent, loadedReplies) = try await (parentTask, repliesTask)
            parentComment = loadedParent
            replies = repliesWithFallback(loadedReplies.replies)
            hasReachedEndOfReplies = loadedReplies.hasReachedEnd
            nextReplyCursor = loadedReplies.nextCursor
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }

        isLoading = false
    }

    private func loadParentCommentIfPossible() async throws -> ExploreComment? {
        guard let parentCommentId = route.parentCommentId else { return nil }

        var cursor: ExploreCommentCursor?

        for _ in 0..<20 {
            let page = try await MerianNetworkClient.shared.getExploreComments(
                postId: route.post.id,
                limit: commentsPageSize,
                afterCreatedAt: cursor?.createdAt,
                afterCommentId: cursor?.commentId
            )

            if let comment = page.first(where: { $0.id == parentCommentId }) {
                return comment
            }

            guard page.count == commentsPageSize, let lastComment = page.last else { break }
            cursor = ExploreCommentCursor(createdAt: lastComment.createdAt, commentId: lastComment.id)
        }

        return nil
    }

    private func loadRepliesThroughTarget() async throws -> LoadedRepliesPage {
        guard let parentCommentId = route.parentCommentId else {
            return LoadedRepliesPage(replies: [], hasReachedEnd: true, nextCursor: nil)
        }

        var loadedReplies: [ExploreComment] = []
        var cursor: ExploreCommentCursor?
        var hasReachedEnd = true

        for _ in 0..<20 {
            let page = try await MerianNetworkClient.shared.getExploreCommentReplies(
                parentCommentId: parentCommentId,
                limit: repliesPageSize,
                afterCreatedAt: cursor?.createdAt,
                afterCommentId: cursor?.commentId
            )

            appendUnique(page, to: &loadedReplies)
            hasReachedEnd = page.count < repliesPageSize

            if loadedReplies.contains(where: { $0.id == route.targetReplyId }) || hasReachedEnd {
                let nextCursor = page.last.map {
                    ExploreCommentCursor(createdAt: $0.createdAt, commentId: $0.id)
                }
                return LoadedRepliesPage(
                    replies: loadedReplies,
                    hasReachedEnd: hasReachedEnd,
                    nextCursor: hasReachedEnd ? nil : nextCursor
                )
            }

            guard let lastReply = page.last else { break }
            cursor = ExploreCommentCursor(createdAt: lastReply.createdAt, commentId: lastReply.id)
        }

        return LoadedRepliesPage(replies: loadedReplies, hasReachedEnd: hasReachedEnd, nextCursor: cursor)
    }

    @MainActor
    private func loadMoreReplies() async {
        guard let parentCommentId = route.parentCommentId,
              !isLoadingMoreReplies,
              !hasReachedEndOfReplies,
              let nextReplyCursor else { return }

        isLoadingMoreReplies = true
        defer { isLoadingMoreReplies = false }

        do {
            let page = try await MerianNetworkClient.shared.getExploreCommentReplies(
                parentCommentId: parentCommentId,
                limit: repliesPageSize,
                afterCreatedAt: nextReplyCursor.createdAt,
                afterCommentId: nextReplyCursor.commentId
            )

            appendUnique(page, to: &replies)
            replies = repliesWithFallback(replies)
            hasReachedEndOfReplies = page.count < repliesPageSize
            self.nextReplyCursor = hasReachedEndOfReplies
                ? nil
                : page.last.map { ExploreCommentCursor(createdAt: $0.createdAt, commentId: $0.id) }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    private func appendUnique(_ page: [ExploreComment], to replies: inout [ExploreComment]) {
        let existingIds = Set(replies.map(\.id))
        replies.append(contentsOf: page.filter { existingIds.contains($0.id) == false })
    }

    private func repliesWithFallback(_ loadedReplies: [ExploreComment]) -> [ExploreComment] {
        guard loadedReplies.contains(where: { $0.id == route.targetReplyId }) == false,
              let fallbackReplyComment else {
            return loadedReplies
        }

        return [fallbackReplyComment] + loadedReplies
    }

    private var fallbackReplyComment: ExploreComment? {
        guard let body = route.fallbackReply.body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else { return nil }

        return ExploreComment(
            commentId: route.fallbackReply.commentId,
            postId: route.post.id,
            parentCommentId: route.parentCommentId,
            authorUserId: route.fallbackReply.authorUserId ?? "",
            authorName: route.fallbackReply.authorName ?? "Someone",
            authorUsername: nil,
            authorAvatarUrl: nil,
            body: body,
            createdAt: route.fallbackReply.createdAt,
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: false,
            replyCount: nil,
            reactions: nil,
            mentions: nil
        )
    }
}

private struct LoadedRepliesPage {
    let replies: [ExploreComment]
    let hasReachedEnd: Bool
    let nextCursor: ExploreCommentCursor?
}
