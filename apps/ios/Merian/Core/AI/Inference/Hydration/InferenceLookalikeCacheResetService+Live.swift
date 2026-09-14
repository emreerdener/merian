import Foundation

private enum InferenceLookalikeCacheResetRuntime {
    @MainActor static var isInFlight = false
}

extension InferenceLookalikeCacheResetService {
    static let live = Self(
        dependencies: Dependencies(
            needsReset: {
                UserDefaults.standard.integer(
                    forKey: UserDefaultsKeys.localLookalikesCacheResetVersion
                ) < InferenceLookalikeCachePolicy.resetVersion
            },
            scheduleReset: { modelContainer in
                guard !InferenceLookalikeCacheResetRuntime.isInFlight else {
                    return
                }
                InferenceLookalikeCacheResetRuntime.isInFlight = true
                Task.detached(priority: .utility) {
                    let database = BackgroundDatabaseActor(
                        modelContainer: modelContainer
                    )
                    await database.clearAllLocalLookalikesCache()
                    await MainActor.run {
                        UserDefaults.standard.set(
                            InferenceLookalikeCachePolicy.resetVersion,
                            forKey: UserDefaultsKeys
                                .localLookalikesCacheResetVersion
                        )
                        InferenceLookalikeCacheResetRuntime.isInFlight = false
                    }
                }
            }
        )
    )
}
