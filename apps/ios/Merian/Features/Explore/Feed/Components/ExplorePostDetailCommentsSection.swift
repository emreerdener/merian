import SwiftUI

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
    var allowsAuthorProfilePresentation = true
    var onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)?

    @State private var reactingCommentId: String?
    @State private var selectedAuthorProfileRoute: ExploreAuthorProfileRoute?
    @State private var localReplyStateVersion: UInt64 = 0

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
                .sheet(item: $selectedAuthorProfileRoute) { route in
                    ExploreAuthorProfileSheet(viewModel: viewModel, route: route)
                        .exploreVideoPresentedOverlayLifecycle(
                            reason: "explore-detail-comments-author-profile"
                        )
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
        ExploreCommentThreadList(
            viewModel: viewModel,
            post: post,
            layout: .detail,
            targetCommentId: targetCommentId,
            targetReplyParentCommentId: targetReplyParentCommentId,
            isComposerFocused: isComposerFocused,
            reactingCommentId: $reactingCommentId,
            onOpenAuthorProfile: authorProfileHandler
        )
    }

    private var composer: some View {
        ExploreCommentComposer(
            viewModel: viewModel,
            post: post,
            isComposerFocused: isComposerFocused,
            onDismissComposer: onDismissComposer
        )
    }

    private var authorProfileHandler: ((ExploreAuthorProfileRoute) -> Void)? {
        guard allowsAuthorProfilePresentation else { return nil }
        return { route in
            openAuthorProfile(route)
        }
    }

    private func openAuthorProfile(_ route: ExploreAuthorProfileRoute) {
        guard allowsAuthorProfilePresentation else { return }
        if let onOpenAuthorProfile {
            onOpenAuthorProfile(route)
        } else {
            selectedAuthorProfileRoute = route
        }
    }
}
