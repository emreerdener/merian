import SwiftUI

struct ExploreMapDiscoveriesSheet: View {
    @Bindable var viewModel: ExploreMapViewModel
    @Bindable var feedViewModel: ExploreFeedViewModel
    @Binding var isPresented: Bool

    let onOpen: (ExplorePost, Bool) -> Void
    let onLike: (ExplorePost) -> Void
    let onUnshare: (ExplorePost) -> Void
    let onBlock: (ExplorePost) -> Void
    let onReport: (ExplorePost) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.visiblePosts) { mapPost in
                        let post = feedViewModel.post(id: mapPost.id) ?? mapPost.asExplorePost
                        ExploreMapPreviewCard(
                            post: post,
                            speciesDisplayName: feedViewModel.resolvedSpeciesCommonName(for: post),
                            mediaReloadGeneration: feedViewModel.mediaReloadGeneration,
                            onOpen: { open(post, focusCommentComposer: false) },
                            onComments: { open(post, focusCommentComposer: true) },
                            onLike: { onLike(post) },
                            onUnshare: { onUnshare(post) },
                            onBlock: { onBlock(post) },
                            onReport: { onReport(post) },
            onReaction: { emoji, selected in Task { await feedViewModel.setPostReaction(for: post, emoji: emoji, selected: selected) } },
            onLoadMoreReactions: { Task { await feedViewModel.loadMorePostReactions(for: post) } }
                        )
                        .task(id: post.id) { await feedViewModel.hydratePostReactions(for: post) }
                    }
                }
                .padding()
            }
            .transparentTopToolbar()
            .navigationTitle(
                ExploreMapPresentation.discoveriesInViewLabel(
                    count: viewModel.visiblePosts.count
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func open(_ post: ExplorePost, focusCommentComposer: Bool) {
        isPresented = false
        onOpen(post, focusCommentComposer)
    }
}
