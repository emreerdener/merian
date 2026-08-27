import SwiftUI

struct ExploreShellEventFeedbackModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let feedViewModel: ExploreFeedViewModel
    let mapViewModel: ExploreMapViewModel
    let dependencies: ExploreShellDependencies

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await feedViewModel.refreshUnreadNotificationCount() }
            }
            .onReceive(dependencies.appEvents) { event in
                switch event {
                case .explorePostNeedsRefresh(let postId):
                    Task { await feedViewModel.refreshPost(postId: postId) }
                case .publicAuthorIdentityChanged:
                    Task {
                        await feedViewModel.refreshFeed()
                        mapViewModel.syncPosts(from: feedViewModel.store.allPosts)
                    }
                default:
                    break
                }
            }
            .merianSystemFeedback(
                toast: Binding(
                    get: { feedViewModel.toastMessage },
                    set: { feedViewModel.toastMessage = $0 }
                ),
                toastAlignment: .top
            )
    }
}
