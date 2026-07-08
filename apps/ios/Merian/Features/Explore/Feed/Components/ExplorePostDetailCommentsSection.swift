import SwiftUI

enum ExploreCommentScrollTarget {
    case comment(String)
    case reply(String)

    var id: String {
        switch self {
        case .comment(let commentId):
            return "explore-comment-\(commentId)"
        case .reply(let replyId):
            return "explore-reply-\(replyId)"
        }
    }
}

struct ExploreReplyRenderInvalidationAnchor: View {
    let version: UInt64

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .transaction { _ in _ = version }
    }
}

struct ExplorePostDetailCommentsSection: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let post: ExplorePost
    let composerId: String
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let isComposerFocused: FocusState<Bool>.Binding
    let onDismissComposer: () -> Void
    let isComposerSticky: Bool
    var hideInlineComposer: Bool = false

    @State private var reactingCommentId: String?
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var localReplyStateVersion: UInt64 = 0

    private let replyThreadParentExtension: CGFloat = 36
    private let replyThreadRowSpacing: CGFloat = 10
    private let replyThreadLineColor = Color(uiColor: .systemGray4)

    var body: some View {
        Group {
            if isComposerSticky {
                composer
                    .background(
                        Color(uiColor: .systemBackground)
                            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -3)
                            .ignoresSafeArea(edges: .bottom)
                    )
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if viewModel.isCommentsLoading && viewModel.comments.isEmpty {
                        loadingState
                    } else if viewModel.comments.isEmpty {
                        emptyState
                    } else {
                        commentsList
                    }

                    if !hideInlineComposer {
                        composer
                            .padding(.top, 8)
                            .id(composerId)
                    }
                }
                .exploreVideoOverlayLifecycle(
                    isPresented: selectedAuthorProfileRoute != nil,
                    reason: "explore-detail-comments-author-profile"
                )
                .sheet(item: $selectedAuthorProfileRoute) { route in
                    ExploreAuthorProfileSheet(viewModel: viewModel, route: route)
                }
            }
        }
        .background {
            ExploreReplyRenderInvalidationAnchor(version: localReplyStateVersion)
        }
        .onChange(of: viewModel.replyStateVersion) { _, newValue in
            localReplyStateVersion = newValue
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "bubble.right")
                    .foregroundColor(.secondary)
                Text("Comments")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
            }

            Spacer()

            Text(post.commentCount.formatted(.number.notation(.compactName)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading comments...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "bubble.left.and.bubble.right",
            title: "No comments yet",
            message: "Be the first to leave a note on this discovery."
        )
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
    }

    private var commentsList: some View {
        LazyVStack(spacing: 14) {
            ForEach(viewModel.comments) { comment in
                commentThreadWithScrollAnchors(comment)
            }

            if viewModel.isLoadingMoreComments {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func commentThreadWithScrollAnchors(_ comment: ExploreComment) -> some View {
        let thread = commentThread(comment)
            .id(ExploreCommentScrollTarget.comment(comment.id).id)
            .onAppear {
                Task { await viewModel.loadMoreCommentsIfNeeded(currentComment: comment) }
            }

        if let fallbackReplyScrollId = fallbackReplyScrollId(for: comment) {
            thread.id(fallbackReplyScrollId)
        } else {
            thread
        }
    }

    private var composer: some View {
        ExploreCommentComposer(
            viewModel: viewModel,
            post: post,
            isComposerFocused: isComposerFocused,
            onDismissComposer: onDismissComposer
        )
    }

    private func commentThread(_ comment: ExploreComment) -> some View {
        let replyState = viewModel.replyThreadRenderState(for: comment.id)

        return VStack(alignment: .leading, spacing: 10) {
            commentRow(comment, allowsReply: true)

            let replyCount = comment.replyCount ?? 0
            if replyCount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    replyCountLabel(replyCount, for: comment)

                    if replyState.isExpanded {
                        repliesList(for: comment, replyState: replyState)
                    } else {
                        replyPreview(for: comment, replyCount: replyCount, replyState: replyState)
                    }
                }

                if !replyState.replies.isEmpty {
                    threadReplyButton(for: comment)
                }
            }
        }
    }

    private func replyCountLabel(_ replyCount: Int, for comment: ExploreComment) -> some View {
        Button(action: {
            Task { await viewModel.expandRepliesAndLoad(for: comment) }
        }) {
            Text("\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 48)
        .task {
            print("[UIRepliesDebug] replyCountLabel task started for comment \(comment.id)")
            defer {
                print("[UIRepliesDebug] replyCountLabel task ended for comment \(comment.id) - isCancelled: \(Task.isCancelled)")
            }
            await viewModel.loadReplyPreviewIfNeeded(for: comment)
        }
    }

    private func threadReplyButton(for comment: ExploreComment) -> some View {
        Button(action: {
            viewModel.beginReply(to: comment)
            isComposerFocused.wrappedValue = true
        }) {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 48)
    }

    @ViewBuilder
    private func replyPreview(
        for comment: ExploreComment,
        replyCount: Int,
        replyState: ExploreReplyThreadRenderState
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if replyState.isLoadingPreview, replyState.replies.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.leading, 48)
            }

            if let firstReply = replyState.replies.first {
                replyRow(firstReply, topExtension: replyThreadParentExtension, connectsToNext: false)

                if replyCount > 1 {
                    Button(action: {
                        Task { await viewModel.expandRepliesAndLoad(for: comment) }
                    }) {
                        Text(showMoreRepliesTitle(for: replyCount))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 48)
                }
            }
        }
    }

    private func showMoreRepliesTitle(for replyCount: Int) -> String {
        let remainingReplyCount = replyCount - 1
        return remainingReplyCount == 1 ? "Show other reply" : "Show \(remainingReplyCount) more replies"
    }

    @ViewBuilder
    private func repliesList(for comment: ExploreComment, replyState: ExploreReplyThreadRenderState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !replyState.hasLoadedReplies {
                if replyState.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.leading, 48)
                } else if replyState.didFail {
                    Button(action: {
                        Task { await viewModel.loadReplies(for: comment) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry loading replies")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 48)
                } else {
                    Button(action: {
                        Task { await viewModel.loadReplies(for: comment) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                            Text("Load replies")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 48)
                }
            }

            ForEach(Array(replyState.replies.enumerated()), id: \.element.id) { index, reply in
                replyRow(
                    reply,
                    topExtension: index > 0 ? replyThreadRowSpacing / 2 : replyThreadParentExtension,
                    connectsToNext: index < replyState.replies.count - 1
                )
                    .onAppear {
                        Task { await viewModel.loadMoreRepliesIfNeeded(parentComment: comment, currentReply: reply) }
                    }
            }

            if replyState.isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.leading, 48)
            } else if replyState.hasLoadedReplies,
                      !replyState.hasReachedEnd,
                      let lastReply = replyState.replies.last {
                Button(action: {
                    Task { await viewModel.loadMoreRepliesIfNeeded(parentComment: comment, currentReply: lastReply) }
                }) {
                    Text("Load more replies")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 48)
            }
        }
    }

    private func replyRow(_ reply: ExploreComment, topExtension: CGFloat, connectsToNext: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ReplyThreadConnector(
                topExtension: topExtension,
                bottomExtension: connectsToNext ? replyThreadRowSpacing / 2 : 0
            )
                .stroke(
                    replyThreadLineColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .round)
                )
                .frame(width: 16)
                .accessibilityHidden(true)

            commentRow(reply, allowsReply: false)
        }
        .id(ExploreCommentScrollTarget.reply(reply.id).id)
        .padding(.leading, 18)
    }

    private func fallbackReplyScrollId(for comment: ExploreComment) -> String? {
        guard targetReplyParentCommentId == comment.id, let targetCommentId else {
            return nil
        }
        guard targetCommentId != comment.id else {
            return nil
        }

        guard viewModel.replyThreadRenderState(for: comment.id).replies.contains(where: { $0.id == targetCommentId }) != true else {
            return nil
        }

        return ExploreCommentScrollTarget.reply(targetCommentId).id
    }

    private struct ReplyThreadConnector: Shape {
        let topExtension: CGFloat
        let bottomExtension: CGFloat

        func path(in rect: CGRect) -> Path {
            let radius = min(rect.width, 8)
            let midY = rect.midY
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY - topExtension))
            path.addLine(to: CGPoint(x: rect.minX, y: connectsBelow ? rect.maxY + bottomExtension : midY - radius))
            if connectsBelow {
                path.move(to: CGPoint(x: rect.minX, y: midY - radius))
            }
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: midY),
                control: CGPoint(x: rect.minX, y: midY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            return path
        }

        private var connectsBelow: Bool {
            bottomExtension > 0
        }
    }

    private func commentRow(_ comment: ExploreComment, allowsReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    authorAvatarView(for: comment)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(comment.displayAuthorName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if let createdAtText = createdAtText(for: comment) {
                            Text(createdAtText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openAuthorProfile(for: comment)
                }

                Spacer()

                if comment.hasOverflowActions {
                    Menu {
                        if comment.viewerCanDelete || comment.viewerCanModerate {
                            Button(role: .destructive) {
                                Task { await viewModel.removeComment(comment) }
                            } label: {
                                Label(comment.removalActionTitle, systemImage: "trash")
                            }
                            .tint(.red)
                        }

                        if comment.viewerCanReport {
                            Button(role: .destructive) {
                                Task { await viewModel.reportComment(comment) }
                            } label: {
                                Label("Report comment", systemImage: "flag")
                            }
                            .tint(.red)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                    }
                    .tint(.primary)
                }
            }

            ExploreCommentBodyText(comment: comment) { mention in
                openMentionProfile(mention)
            }

            ExploreCommentReactionsView(
                comment: comment,
                reactingCommentId: $reactingCommentId,
                onToggleReaction: { comment, emoji in
                    viewModel.toggleReaction(for: comment, emoji: emoji)
                }
            )

            if allowsReply {
                Button(action: {
                    viewModel.beginReply(to: comment)
                    isComposerFocused.wrappedValue = true
                }) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func openAuthorProfile(for comment: ExploreComment) {
        HapticManager.shared.triggerSelectionPulse()
        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(comment: comment)
    }

    private func openMentionProfile(_ mention: ExploreCommentMention) {
        HapticManager.shared.triggerSelectionPulse()
        selectedAuthorProfileRoute = ExploreAuthorProfileRoute(mention: mention)
    }

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
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
                    fallbackCommentAuthorAvatar
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackCommentAuthorAvatar
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            fallbackCommentAuthorAvatar
        }
    }

    private var fallbackCommentAuthorAvatar: some View {
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

        if post.authorUserId.lowercased() == comment.authorUserId.lowercased(),
           let postAvatarUrlString = post.authorAvatarUrl,
           let postAvatarUrl = URL(string: postAvatarUrlString) {
            return postAvatarUrl
        }

        return nil
    }
}
