import SwiftData
import SwiftUI

struct ExploreHashtagPostsView: View {
    @Bindable var viewModel: ExploreFeedViewModel
    let route: ExploreHashtagRoute
    let allowsInsightPresentation: Bool
    let onOpenOwnedPostInsight: ((String) -> Bool)?
    var allowsAuthorProfilePresentation = true
    var authorProfileDepth = 0
    var onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)?

    @Environment(ExploreVideoPlaybackCoordinator.self) private var playbackCoordinator: ExploreVideoPlaybackCoordinator?
    @Environment(\.modelContext) private var modelContext

    @State private var postsViewModel: ExploreHashtagPostsViewModel
    @State private var selectedPostRoute: ExplorePostRoute?

    init(
        viewModel: ExploreFeedViewModel,
        route: ExploreHashtagRoute,
        allowsInsightPresentation: Bool,
        onOpenOwnedPostInsight: ((String) -> Bool)?,
        allowsAuthorProfilePresentation: Bool = true,
        authorProfileDepth: Int = 0,
        onOpenAuthorProfile: ((ExploreAuthorProfileRoute) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.route = route
        self.allowsInsightPresentation = allowsInsightPresentation
        self.onOpenOwnedPostInsight = onOpenOwnedPostInsight
        self.allowsAuthorProfilePresentation = allowsAuthorProfilePresentation
        self.authorProfileDepth = authorProfileDepth
        self.onOpenAuthorProfile = onOpenAuthorProfile
        _postsViewModel = State(
            initialValue: ExploreHashtagPostsViewModel(hashtag: route.hashtag)
        )
    }

    var body: some View {
        Group {
            if postsViewModel.isLoadingInitialPage && postsViewModel.posts.isEmpty {
                loadingState
            } else if let errorMessage = postsViewModel.errorMessage,
                      postsViewModel.posts.isEmpty {
                errorState(message: errorMessage)
            } else if postsViewModel.posts.isEmpty {
                emptyState
            } else {
                postsGrid
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("#\(route.hashtag)")
        .navigationDestination(
            isPresented: Binding(
                get: { selectedPostRoute != nil },
                set: { if !$0 { selectedPostRoute = nil } }
            )
        ) {
            if let selectedPostRoute {
                ExplorePostDetailView(
                    viewModel: viewModel,
                    postId: selectedPostRoute.postId,
                    shouldFocusCommentComposer: selectedPostRoute.shouldFocusCommentComposer,
                    shouldOpenInsight: selectedPostRoute.shouldOpenInsight,
                    targetCommentId: selectedPostRoute.targetCommentId,
                    targetReplyParentCommentId: selectedPostRoute.targetReplyParentCommentId,
                    allowsInsightPresentation: allowsInsightPresentation,
                    onOpenOwnedPostInsight: onOpenOwnedPostInsight,
                    allowsAuthorProfilePresentation: allowsAuthorProfilePresentation &&
                        ExploreAuthorProfileNavigationPolicy.canOpenProfile(from: selectedPostRoute.authorProfileDepth),
                    authorProfileDepth: selectedPostRoute.authorProfileDepth,
                    onOpenAuthorProfile: onOpenAuthorProfile
                )
            }
        }
        .task(id: route.hashtag) {
            await reloadPosts()
        }
    }

    private var postsGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 16) {
                ForEach(postsViewModel.posts) { source in
                    let post = viewModel.post(id: source.id) ?? source
                    VStack(spacing: 0) {
                    Button {
                        openPost(post)
                    } label: {
                        ExploreHeroImageView(
                            imageUrl: post.heroImageUrl,
                            reloadGeneration: viewModel.mediaReloadGeneration,
                            maxDimension: 960
                        )
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            if post.hasVideoMedia || post.hasAudioMedia {
                                ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                                    .padding(8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(viewModel.resolvedSpeciesCommonName(for: post)), tagged #\(route.hashtag)")
                    ExplorePostReactionBar(post: post,
                        onComments: { Task { await viewModel.openCommentsSheet(for: post) } },
                        onLike: { Task { await viewModel.toggleLike(for: post) } },
                        onReaction: { emoji, selected in Task { await viewModel.setPostReaction(for: post, emoji: emoji, selected: selected) } },
                        onLoadMore: { Task { await viewModel.loadMorePostReactions(for: post) } },
                        onShare: { viewModel.share(post, playbackCoordinator: playbackCoordinator) })
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .onAppear {
                        guard post.id == postsViewModel.posts.last?.id else { return }
                        Task { await loadMorePostsIfNeeded() }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)

            if postsViewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
        }
        .transparentTopToolbar()
        .refreshable {
            await reloadPosts()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading tagged posts...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            iconName: "number",
            title: "No tagged posts",
            message: "Visible Explore posts tagged #\(route.hashtag) will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        ExploreUnavailableStateView(
            title: "Hashtag unavailable",
            message: message
        ) {
            Task { await reloadPosts() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func reloadPosts() async {
        let reactionSnapshot = viewModel.reactionRevisions
        await postsViewModel.reload()
        registerPosts(viewModel.preservingNewerReactions(in: postsViewModel.posts, since: reactionSnapshot))
    }

    @MainActor
    private func loadMorePostsIfNeeded() async {
        let existingIDs = Set(postsViewModel.posts.map(\.id))
        let reactionSnapshot = viewModel.reactionRevisions
        if let errorMessage = await postsViewModel.loadMoreIfNeeded() {
            viewModel.toastMessage = .error(errorMessage)
        }
        let newPosts = postsViewModel.posts.filter { !existingIDs.contains($0.id) }
        registerPosts(viewModel.preservingNewerReactions(in: newPosts, since: reactionSnapshot))
    }

    @MainActor
    private func registerPosts(_ page: [ExplorePost]) {
        for post in page {
            viewModel.upsertPost(post)
        }
        viewModel.refreshPreferredSpeciesNames(
            for: page.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    @MainActor
    private func openPost(_ post: ExplorePost) {
        if viewModel.post(id: post.id) == nil { viewModel.upsertPost(post) }
        selectedPostRoute = ExplorePostRoute(
            postId: post.id,
            shouldFocusCommentComposer: false,
            shouldOpenInsight: false,
            targetCommentId: nil,
            targetReplyParentCommentId: nil,
            authorProfileDepth: authorProfileDepth
        )
    }
}
