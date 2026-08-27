import SwiftData
import SwiftUI

struct ExploreShellPresentationModifier: ViewModifier {
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext

    let feedViewModel: ExploreFeedViewModel
    @Binding var selectedInsightRoute: ScanInsightRoute?
    let onNotificationsDismiss: () -> Void
    let onOpenNotification: @MainActor (ExploreNotification) async -> Void
    let onStageInsightCommunityRequest: (String) -> Void
    let onResumeInsightCommunityRequest: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: Binding(
                    get: { feedViewModel.isCommentsSheetPresented },
                    set: { if !$0 { feedViewModel.dismissCommentsSheet() } }
                ),
                onDismiss: {}
            ) {
                Group {
                    if let post = feedViewModel.activeCommentsPost {
                        ExploreCommentsSheet(viewModel: feedViewModel, post: post)
                    }
                }
                .exploreVideoPresentedOverlayLifecycle(reason: "explore-root-comments-sheet")
            }
            .sheet(
                isPresented: Binding(
                    get: { feedViewModel.isNotificationsSheetPresented },
                    set: { if !$0 { feedViewModel.dismissNotifications() } }
                ),
                onDismiss: {
                    onNotificationsDismiss()
                    Task {
                        await feedViewModel.refreshUnreadNotificationCount(force: true)
                    }
                }
            ) {
                ExploreNotificationsSheet(
                    onUnreadNotificationsCleared: {
                        feedViewModel.unreadNotificationCount = 0
                        AppIconBadgeCoordinator.clearExploreUnreadNotificationCount()
                    },
                    onOpenNotification: onOpenNotification
                )
                .exploreVideoPresentedOverlayLifecycle(
                    reason: "explore-root-notifications-sheet"
                )
            }
            .sheet(
                item: $selectedInsightRoute,
                onDismiss: {
                    feedViewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
                    onResumeInsightCommunityRequest()
                }
            ) { route in
                LocalScanInsightLoader(scanId: route.scanId) {
                    InsightSheetView(
                        isPresented: Binding(
                            get: { selectedInsightRoute != nil },
                            set: { if !$0 { selectedInsightRoute = nil } }
                        ),
                        initialScanId: route.scanId,
                        inferenceEngine: inferenceEngine,
                        allowsExplorePresentation: false,
                        onOpenCommunityIdentificationRequest: { requestId in
                            onStageInsightCommunityRequest(requestId)
                            selectedInsightRoute = nil
                        }
                    )
                }
                .exploreVideoPresentedOverlayLifecycle(reason: "explore-root-insight-sheet")
            }
    }
}
