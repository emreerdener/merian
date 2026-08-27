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

enum ExploreCommentThreadLayout {
    case sheet
    case detail

    var authorAlignment: VerticalAlignment {
        switch self {
        case .sheet: .center
        case .detail: .top
        }
    }

    var authorSpacing: CGFloat {
        switch self {
        case .sheet: 8
        case .detail: 12
        }
    }

    var usesScrollAnchors: Bool {
        self == .detail
    }
}

struct ExploreCommentThreadList: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let post: ExplorePost
    let layout: ExploreCommentThreadLayout
    let targetCommentId: String?
    let targetReplyParentCommentId: String?
    let isComposerFocused: FocusState<Bool>.Binding
    @Binding var reactingCommentId: String?
    var onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)?

    private let replyThreadParentExtension: CGFloat = 36
    private let replyThreadRowSpacing: CGFloat = 10
    private let replyThreadLineColor = Color(uiColor: .systemGray4)

    var body: some View {
        LazyVStack(spacing: 14) {
            ForEach(viewModel.comments) { comment in
                commentThreadContainer(comment)
            }

            if viewModel.isLoadingMoreComments {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func commentThreadContainer(_ comment: ExploreComment) -> some View {
        if layout.usesScrollAnchors {
            let anchoredThread = commentThread(comment)
                .id(ExploreCommentScrollTarget.comment(comment.id).id)
                .onAppear {
                    Task {
                        await viewModel.loadMoreCommentsIfNeeded(currentComment: comment)
                    }
                }
            if let fallbackReplyScrollId = fallbackReplyScrollId(for: comment) {
                anchoredThread.id(fallbackReplyScrollId)
            } else {
                anchoredThread
            }
        } else {
            commentThread(comment)
                .onAppear {
                    Task {
                        await viewModel.loadMoreCommentsIfNeeded(currentComment: comment)
                    }
                }
        }
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
                replyRow(
                    firstReply,
                    topExtension: replyThreadParentExtension,
                    connectsToNext: false
                )

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
        return remainingReplyCount == 1
            ? "Show other reply"
            : "Show \(remainingReplyCount) more replies"
    }

    @ViewBuilder
    private func repliesList(
        for comment: ExploreComment,
        replyState: ExploreReplyThreadRenderState
    ) -> some View {
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
                    topExtension: index > 0
                        ? replyThreadRowSpacing / 2
                        : replyThreadParentExtension,
                    connectsToNext: index < replyState.replies.count - 1
                )
                .onAppear {
                    Task {
                        await viewModel.loadMoreRepliesIfNeeded(
                            parentComment: comment,
                            currentReply: reply
                        )
                    }
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
                    Task {
                        await viewModel.loadMoreRepliesIfNeeded(
                            parentComment: comment,
                            currentReply: lastReply
                        )
                    }
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

    @ViewBuilder
    private func replyRow(
        _ reply: ExploreComment,
        topExtension: CGFloat,
        connectsToNext: Bool
    ) -> some View {
        let row = HStack(alignment: .top, spacing: 0) {
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

        if layout.usesScrollAnchors {
            row
                .id(ExploreCommentScrollTarget.reply(reply.id).id)
                .padding(.leading, 18)
        } else {
            row.padding(.leading, 18)
        }
    }

    private func fallbackReplyScrollId(for comment: ExploreComment) -> String? {
        guard targetReplyParentCommentId == comment.id, let targetCommentId else {
            return nil
        }
        guard targetCommentId != comment.id else { return nil }

        let hasLoadedTarget = viewModel.replyThreadRenderState(for: comment.id)
            .replies
            .contains(where: { $0.id == targetCommentId })
        guard !hasLoadedTarget else { return nil }

        return ExploreCommentScrollTarget.reply(targetCommentId).id
    }

    private func commentRow(_ comment: ExploreComment, allowsReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: layout.authorAlignment, spacing: layout.authorSpacing) {
                HStack(alignment: layout.authorAlignment, spacing: layout.authorSpacing) {
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
                    openAuthorProfile(ExploreAuthorProfileRoute(comment: comment))
                }

                Spacer()

                if comment.hasOverflowActions {
                    commentActions(for: comment)
                }
            }

            ExploreCommentBodyText(comment: comment) { mention in
                openAuthorProfile(ExploreAuthorProfileRoute(mention: mention))
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

    private func commentActions(for comment: ExploreComment) -> some View {
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

    private func openAuthorProfile(_ route: ExploreAuthorProfileRoute) {
        guard let onOpenAuthorProfile else { return }
        HapticManager.shared.triggerSelectionPulse()
        onOpenAuthorProfile(route)
    }

    private func createdAtText(for comment: ExploreComment) -> String? {
        guard let createdAtDate = comment.createdAtDate else { return nil }
        return createdAtDate.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private func authorAvatarView(for comment: ExploreComment) -> some View {
        if let avatarUrl = viewModel.commentAuthorAvatarURL(for: comment, post: post) {
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

    private struct ReplyThreadConnector: Shape {
        let topExtension: CGFloat
        let bottomExtension: CGFloat

        func path(in rect: CGRect) -> Path {
            let radius = min(rect.width, 8)
            let midY = rect.midY
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY - topExtension))
            path.addLine(
                to: CGPoint(
                    x: rect.minX,
                    y: connectsBelow ? rect.maxY + bottomExtension : midY - radius
                )
            )
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
}
