import SwiftUI

extension ExploreMapView {
    func openPost(_ post: ExplorePost, focusCommentComposer: Bool) {
        AppTelemetry.trackExploreMapDetailOpened(
            entryPoint: focusCommentComposer ? "comments" : "preview"
        )
        feedViewModel.upsertPost(post)
        onOpenDetail(post, focusCommentComposer)
    }

    func openSelectedPost(focusCommentComposer: Bool) {
        guard let selectedPost = resolvedSelectedPost else { return }
        openPost(selectedPost, focusCommentComposer: focusCommentComposer)
    }

    func toggleLike(for post: ExplorePost) async {
        feedViewModel.upsertPost(post)
        await feedViewModel.toggleLike(for: post)
        viewModel.syncPosts(from: postStore.allPosts)
    }

    func unshare(_ post: ExplorePost) async {
        guard await feedViewModel.unshare(post) else { return }
        viewModel.removePost(id: post.id)
    }

    func blockAuthor(of post: ExplorePost) async {
        guard await feedViewModel.blockAuthor(of: post) else { return }
        viewModel.removePosts(byAuthorUserId: post.authorUserId)
    }

    func report(_ post: ExplorePost) async {
        guard await feedViewModel.report(post) else { return }
        viewModel.removePost(id: post.id)
    }

    func dismissSelectedPostIfNeeded() {
        guard !ignoreNextBackgroundTap, viewModel.selectedPostId != nil else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            viewModel.selectPost(nil)
        }
    }

    func registerAnnotationTap() {
        ignoreNextBackgroundTap = true

        Task { @MainActor in
            await Task.yield()
            ignoreNextBackgroundTap = false
        }
    }
}
