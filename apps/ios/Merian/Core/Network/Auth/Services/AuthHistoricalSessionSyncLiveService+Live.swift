import Foundation

extension HistoricalSessionSyncLiveDependencies {
    @MainActor
    static let live = Self(
        makeWork: {
            guard let context = AppDIContainer.shared.offlineQueueManager
                .modelContext else {
                return nil
            }
            return AuthHistoricalSessionSyncWork(
                markStarted: {
                    UserDefaults.standard.set(
                        Date(),
                        forKey: UserDefaultsKeys.lastHistoricalSyncDate
                    )
                },
                syncPreferredNames: {
                    await SpeciesPreferredNameRepository
                        .syncCloudPreferences(modelContext: context)
                },
                syncHistoricalScans: {
                    await AppDIContainer.shared.scanRepository
                        .syncHistoricalScansDown(modelContext: context)
                }
            )
        }
    )
}
