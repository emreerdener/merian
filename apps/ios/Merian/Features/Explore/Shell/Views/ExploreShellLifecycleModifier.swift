import SwiftData
import SwiftUI

private struct ExploreNotificationSessionKey: Hashable {
    let userID: UUID?
    let authTransitionInProgress: Bool
}

struct ExploreShellLifecycleModifier: ViewModifier {
    @Environment(AppSettings.self) private var appSettings
    @Environment(SupabaseManager.self) private var supabase
    @Environment(\.modelContext) private var modelContext

    let feedViewModel: ExploreFeedViewModel
    let activeTab: ExploreTab
    let activeDiscoveryMode: ExploreDiscoveryMode
    let activeIdentifyMode: ExploreIdentifyMode
    let triggerSelectionFeedback: @MainActor () -> Void
    let refreshDictionaryUserRegion: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content
            .task {
                feedViewModel.bindSettings(appSettings)
                await feedViewModel.loadInitialFeed()
                feedViewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
            }
            .onChange(of: feedViewModel.store.changeVersion) { _, _ in
                feedViewModel.refreshPreferredSpeciesNames(modelContext: modelContext)
            }
            .onChange(of: activeDiscoveryMode) { _, newValue in
                triggerSelectionFeedback()
                if newValue == .map {
                    AppTelemetry.trackExploreMapOpened()
                }
            }
            .onChange(of: activeIdentifyMode) { _, _ in
                triggerSelectionFeedback()
            }
            .task(id: activeIdentifyMode) {
                guard activeTab == .community, activeIdentifyMode == .index else { return }
                await refreshDictionaryUserRegion()
            }
            .task(id: activeTab) {
                guard activeTab == .community, activeIdentifyMode == .index else { return }
                await refreshDictionaryUserRegion()
            }
            .task(id: ExploreNotificationSessionKey(
                userID: supabase.currentUser?.id,
                authTransitionInProgress: supabase.isAuthTransitionInProgress
            )) {
                feedViewModel.stopUnreadNotificationUpdates()
                guard supabase.allowsUnownedAccountBoundWork else { return }
                await feedViewModel.startUnreadNotificationUpdates()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    guard !Task.isCancelled else { break }
                    await feedViewModel.refreshUnreadNotificationCount()
                }
            }
            .onDisappear {
                feedViewModel.stopUnreadNotificationUpdates()
            }
    }
}
