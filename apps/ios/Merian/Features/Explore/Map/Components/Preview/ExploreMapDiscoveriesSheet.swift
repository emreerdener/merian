import SwiftData
import SwiftUI

struct ExploreMapDiscoveriesSheet: View {
    @Bindable var discoveries: ExploreMapDiscoveriesViewModel
    @Bindable var feedViewModel: ExploreFeedViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var retryGeneration = 0

    let onOpen: (ExplorePost, Bool) -> Void
    let onOpenAuthorProfile: (ExplorePost) -> Void
    let onLike: (ExplorePost) -> Void
    let onUnshare: (ExplorePost) -> Void
    let onBlock: (ExplorePost) -> Void
    let onReport: (ExplorePost) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if discoveries.isLoading || discoveries.isAwaitingLoad {
                        ProgressView("Loading discoveries…")
                            .padding(32)
                    } else if let errorMessage = discoveries.errorMessage {
                        ExploreMapStateCard(
                            title: "Discoveries unavailable",
                            message: errorMessage,
                            actionTitle: "Retry",
                            action: { retryGeneration += 1 }
                        )
                    } else if discoveries.posts.isEmpty {
                        ContentUnavailableView(
                            "No discoveries here",
                            systemImage: "binoculars",
                            description: Text("Return to the map and try another area or adjust your filters.")
                        )
                    }

                    if discoveries.showsResultLimit {
                        Text("Showing \(discoveries.posts.count.formatted()) of \(discoveries.totalCount.formatted()) discoveries. Zoom in on the map to explore a smaller area.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(discoveries.posts.filter { feedViewModel.visibility.isVisible(postID: $0.id) }) { mapPost in
                        let post = feedViewModel.post(id: mapPost.id) ?? mapPost.asExplorePost
                        ExploreMapPreviewCard(
                            post: post,
                            speciesDisplayName: feedViewModel.resolvedSpeciesCommonName(for: post),
                            mediaReloadGeneration: feedViewModel.mediaReloadGeneration,
                            onOpen: { open(post, focusCommentComposer: false) },
                            onOpenAuthorProfile: {
                                dismiss()
                                onOpenAuthorProfile(post)
                            },
                            onComments: { open(post, focusCommentComposer: true) },
                            onLike: { onLike(post) },
                            onUnshare: { onUnshare(post) },
                            onBlock: { onBlock(post) },
                            onReport: { onReport(post) },
                            onReaction: { emoji, selected in
                                Task { await feedViewModel.setPostReaction(for: post, emoji: emoji, selected: selected) }
                            },
                            onLoadMoreReactions: { Task { await feedViewModel.loadMorePostReactions(for: post) } },
                            stacksImageAboveContent: true
                        )
                        .task(id: post.id) { await feedViewModel.hydratePostReactions(for: post) }
                    }
                }
                .padding()
            }
            .transparentTopToolbar()
            .navigationTitle(
                ExploreMapPresentation.discoveriesInViewLabel(
                    count: discoveries.totalCount
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .task(id: retryGeneration) { await discoveries.load() }
        .onDisappear { discoveries.cancelLoading() }
        .onChange(of: discoveries.posts, initial: true) { _, posts in
            feedViewModel.refreshPreferredSpeciesNames(
                for: posts.map(\.speciesScientificName),
                modelContext: modelContext
            )
        }
    }

    private func open(_ post: ExplorePost, focusCommentComposer: Bool) {
        dismiss()
        onOpen(post, focusCommentComposer)
    }
}
