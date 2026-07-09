import SwiftUI

struct ExploreCommentsSheet: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let post: ExplorePost

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var reactingCommentId: String?
    @State private var navigationPath = NavigationPath()
    @State private var localReplyStateVersion: UInt64 = 0
    private let replyThreadLineColor = Color(uiColor: .systemGray4)
    private let replyThreadParentExtension: CGFloat = 36
    private let replyThreadRowSpacing: CGFloat = 10

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isCommentsLoading && viewModel.comments.isEmpty {
                    loadingState
                } else if viewModel.comments.isEmpty {
                    emptyState
                } else {
                    commentsScrollView
                }
            }
            .background(
                ExploreKeyboardDismissTapRecognizer(
                    isEnabled: isComposerFocused,
                    onTap: { isComposerFocused = false }
                )
            )
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Comments")
                            .font(.headline)
                        Text(viewModel.resolvedSpeciesCommonName(for: post))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
                    .background(
                        Color(uiColor: .systemBackground)
                            .ignoresSafeArea(edges: .bottom)
                            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                    )
            }
            .navigationDestination(for: ExploreAuthorProfileRoute.self) { route in
                ExploreAuthorProfileContent(
                    viewModel: viewModel,
                    route: route,
                    presentation: .stack,
                    onClose: popNavigation,
                    onOpenPostRoute: { route in
                        navigationPath.append(route)
                    },
                    onOpenPublication: { publicationId in
                        navigationPath.append(FieldTripPublicationRoute(publicationId: publicationId))
                    }
                )
            }
            .navigationDestination(for: ExplorePostRoute.self) { route in
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: route.postId,
                    shouldFocusCommentComposer: route.shouldFocusCommentComposer,
                    shouldOpenInsight: route.shouldOpenInsight,
                    targetCommentId: route.targetCommentId,
                    targetReplyParentCommentId: route.targetReplyParentCommentId,
                    allowsInsightPresentation: false,
                    allowsAuthorProfilePresentation: ExploreAuthorProfileNavigationPolicy.canOpenProfile(
                        from: route.authorProfileDepth
                    ),
                    authorProfileDepth: route.authorProfileDepth,
                    onOpenAuthorProfile: { authorRoute in
                        appendAuthorProfileRoute(authorRoute, fromDepth: route.authorProfileDepth)
                    }
                )
            }
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
            }
            .navigationDestination(for: FieldTripPublicationRoute.self) { route in
                FieldTripPublicationDetailView(publicationId: route.publicationId)
            }
        }
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
        .onChange(of: viewModel.commentDraft) { _, newValue in
            if newValue.count > 500 {
                viewModel.commentDraft = String(newValue.prefix(500))
            }
        }
        .background {
            ExploreReplyRenderInvalidationAnchor(version: localReplyStateVersion)
        }
        .onChange(of: viewModel.replyStateVersion) { _, newValue in
            localReplyStateVersion = newValue
        }
    }

    private var commentsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.comments) { comment in
                    commentThread(comment)
                        .onAppear {
                            Task { await viewModel.loadMoreCommentsIfNeeded(currentComment: comment) }
                        }
                }

                if viewModel.isLoadingMoreComments {
                    ProgressView()
                        .progressViewStyle(.circular)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading comments...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "bubble.left.and.bubble.right",
            title: "No comments yet",
            message: "Be the first to leave a note on this discovery."
        )
    }

    private var composer: some View {
        ExploreCommentComposer(
            viewModel: viewModel,
            post: post,
            isComposerFocused: $isComposerFocused,
            onDismissComposer: { isComposerFocused = false }
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
            isComposerFocused = true
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
        .padding(.leading, 18)
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
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
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
                    isComposerFocused = true
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
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(comment: comment), fromDepth: 0)
    }

    private func openMentionProfile(_ mention: ExploreCommentMention) {
        HapticManager.shared.triggerSelectionPulse()
        appendAuthorProfileRoute(ExploreAuthorProfileRoute(mention: mention), fromDepth: 0)
    }

    private func appendAuthorProfileRoute(_ route: ExploreAuthorProfileRoute, fromDepth currentDepth: Int) {
        guard ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: currentDepth) else { return }

        navigationPath.append(
            route.withNavigationDepth(
                ExploreAuthorProfileNavigationPolicy.nextProfileDepth(from: currentDepth)
            )
        )
    }

    private func popNavigation() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
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

        if post.authorUserId.lowercased() == comment.authorUserId.lowercased(),
           let postAvatarUrlString = post.authorAvatarUrl,
           let postAvatarUrl = URL(string: postAvatarUrlString) {
            return postAvatarUrl
        }

        return nil
    }
}
