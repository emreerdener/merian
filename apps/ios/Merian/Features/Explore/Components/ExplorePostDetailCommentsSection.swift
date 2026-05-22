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

    private let availableEmojis = ["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F602}", "\u{1F389}", "\u{1F632}", "\u{1F33F}"]
    private let replyThreadParentExtension: CGFloat = 36
    private let replyThreadRowSpacing: CGFloat = 10
    private let replyThreadLineColor = Color(uiColor: .systemGray4)

    var body: some View {
        if isComposerSticky {
            composer
                .padding(.horizontal, 16)
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
        .id(viewModel.replyStateVersion)
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
        VStack(alignment: .leading, spacing: 10) {
            if let commentErrorMessage = viewModel.commentErrorMessage {
                Text(commentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let replyingToComment = viewModel.replyingToComment {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Replying to \(replyingToComment.displayAuthorName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: { viewModel.cancelReply() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                if SupabaseManager.shared.isAuthenticated, let avatarUrl = SupabaseManager.shared.currentUserAvatarUrl {
                    AsyncImage(url: avatarUrl) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                    } placeholder: {
                        Color(uiColor: .tertiarySystemFill)
                            .frame(width: 40, height: 40)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .padding(.bottom, 1)
                }

                TextField(composerPlaceholder, text: $viewModel.commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(isComposerFocused)
                    .id(viewModel.composerResetToken)
                    .submitLabel(.done)
                    .onSubmit {
                        onDismissComposer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                Button(action: {
                    Task { await viewModel.submitComment() }
                }) {
                    ZStack {
                        Circle()
                            .fill(canSubmitComment ? Color.primary : Color.secondary.opacity(0.25))
                            .frame(width: 42, height: 42)

                        if viewModel.isSubmittingComment {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(uiColor: .systemBackground))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(canSubmitComment ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.4))
                        }
                    }
                }
                .disabled(!canSubmitComment || viewModel.isSubmittingComment)
                .buttonStyle(.plain)
            }

            Text("\(viewModel.commentDraft.count)/500")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    if isComposerFocused.wrappedValue && value.translation.height > 10 {
                        onDismissComposer()
                    }
                }
        )
    }

    private var canSubmitComment: Bool {
        !viewModel.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composerPlaceholder: String {
        if let replyingToComment = viewModel.replyingToComment {
            return "Reply to \(replyingToComment.displayAuthorName)"
        }
        return "Add a comment"
    }

    private func commentThread(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            commentRow(comment, allowsReply: true)

            let replyCount = comment.replyCount ?? 0
            if replyCount > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    replyCountLabel(replyCount, for: comment)

                    if viewModel.expandedReplyCommentIds.contains(comment.id) {
                        repliesList(for: comment)
                    } else {
                        replyPreview(for: comment, replyCount: replyCount)
                    }
                }

                if viewModel.repliesByCommentId[comment.id]?.isEmpty == false {
                    threadReplyButton(for: comment)
                }
            }
        }
    }

    private func replyCountLabel(_ replyCount: Int, for comment: ExploreComment) -> some View {
        Button(action: { viewModel.expandReplies(for: comment) }) {
            Text("\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 48)
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
    private func replyPreview(for comment: ExploreComment, replyCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.loadingReplyCommentIds.contains(comment.id),
               viewModel.repliesByCommentId[comment.id]?.isEmpty ?? true {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.leading, 48)
            }

            if let firstReply = viewModel.repliesByCommentId[comment.id]?.first {
                replyRow(firstReply, topExtension: replyThreadParentExtension, connectsToNext: false)

                if replyCount > 1 {
                    Button(action: { viewModel.expandReplies(for: comment) }) {
                        Text(showMoreRepliesTitle(for: replyCount))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 48)
                }
            }
        }
        .task {
            await viewModel.loadReplyPreviewIfNeeded(for: comment)
        }
    }

    private func showMoreRepliesTitle(for replyCount: Int) -> String {
        let remainingReplyCount = replyCount - 1
        return remainingReplyCount == 1 ? "Show other reply" : "Show \(remainingReplyCount) more replies"
    }

    @ViewBuilder
    private func repliesList(for comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.loadingReplyCommentIds.contains(comment.id) && (viewModel.repliesByCommentId[comment.id]?.isEmpty ?? true) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.leading, 48)
            }

            ForEach(Array((viewModel.repliesByCommentId[comment.id] ?? []).enumerated()), id: \.element.id) { index, reply in
                replyRow(
                    reply,
                    topExtension: index > 0 ? replyThreadRowSpacing / 2 : replyThreadParentExtension,
                    connectsToNext: index < (viewModel.repliesByCommentId[comment.id] ?? []).count - 1
                )
                    .onAppear {
                        Task { await viewModel.loadMoreRepliesIfNeeded(parentComment: comment, currentReply: reply) }
                    }
            }

            if viewModel.loadingMoreReplyCommentIds.contains(comment.id) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.leading, 48)
            } else if viewModel.hasLoadedRepliesByCommentId.contains(comment.id),
                      !viewModel.hasReachedEndOfRepliesByCommentId.contains(comment.id),
                      let lastReply = viewModel.repliesByCommentId[comment.id]?.last {
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

        guard viewModel.repliesByCommentId[comment.id]?.contains(where: { $0.id == targetCommentId }) != true else {
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

            Text(comment.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            reactionsView(for: comment)

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

    @ViewBuilder
    private func reactionsView(for comment: ExploreComment) -> some View {
        let reactions = comment.reactions ?? []
        let hasAvailableReactions = availableEmojis.contains { emoji in
            !(reactions.first(where: { $0.emoji == emoji })?.viewerHasReacted ?? false)
        }

        FlowLayout(spacing: 8) {
            ForEach(reactions) { reaction in
                Button(action: {
                    viewModel.toggleReaction(for: comment, emoji: reaction.emoji)
                }) {
                    HStack(spacing: 4) {
                        Text(reaction.emoji)
                            .font(.subheadline)
                        Text("\(reaction.count)")
                            .font(.footnote)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(reaction.viewerHasReacted ? Color.blue.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
                    )
                    .overlay(
                        Capsule()
                            .stroke(reaction.viewerHasReacted ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .foregroundColor(reaction.viewerHasReacted ? .blue : .primary)
                }
                .buttonStyle(.plain)
            }

            if hasAvailableReactions {
                Button {
                    reactingCommentId = comment.id
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "face.smiling")
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { reactingCommentId == comment.id },
                    set: { if !$0 { reactingCommentId = nil } }
                )) {
                    reactionPicker(for: comment)
                }
            }
        }
        .padding(.top, 4)
    }

    private func reactionPicker(for comment: ExploreComment) -> some View {
        HStack(spacing: 8) {
            ForEach(availableEmojis, id: \.self) { emoji in
                let hasReacted = comment.reactions?.first(where: { $0.emoji == emoji })?.viewerHasReacted ?? false

                Button {
                    viewModel.toggleReaction(for: comment, emoji: emoji)
                    reactingCommentId = nil
                } label: {
                    Text(verbatim: emoji)
                        .font(.system(size: 28))
                        .padding(6)
                        .background(
                            Circle()
                                .fill(hasReacted ? Color.blue.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .presentationCompactAdaptation(.popover)
    }
}
