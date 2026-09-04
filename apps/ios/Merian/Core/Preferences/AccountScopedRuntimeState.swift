import Foundation

/// Resets process-local projections after persistent account data is gone.
///
/// Keeping these effects behind one injected boundary prevents feature views
/// and the data repository from reaching into unrelated singletons directly.
@MainActor
enum AccountScopedRuntimeState {
    struct Dependencies {
        let refreshSettings: @MainActor () -> Void
        let resetGamification: @MainActor () -> Void
        let resetAppIconBadge: @MainActor () -> Void
        let clearImageCache: @MainActor () -> Void

        static let live = Dependencies(
            refreshSettings: {
                AppSettings.shared.refreshFromDefaults()
            },
            resetGamification: {
                GamificationManager.shared.resetAccountState()
            },
            resetAppIconBadge: {
                AppIconBadgeCoordinator.resetAccountState()
            },
            clearImageCache: {
                ImageCache.shared.clearCache()
            }
        )
    }

    static func reset(dependencies: Dependencies = .live) {
        dependencies.refreshSettings()
        dependencies.resetGamification()
        dependencies.resetAppIconBadge()
        dependencies.clearImageCache()
    }
}
