import Foundation

/// Live library effects stay outside Settings presentation. The snapshot closure
/// reads observable restoration state so progress continues to invalidate views.
@MainActor
struct LibraryTransitionPresentationDependencies {
    struct Restoration {
        let accountID: UUID?
        let status: LibraryRestorationState.Status
    }

    var restoration: () -> Restoration
    var openScan: (String) -> Void
    var openLibrary: () -> Void
    var retryScan: (String) -> Void
    var retrySynchronization: () async -> Void

    static var live: Self {
        Self(restoration: {
            let state = ScanRepository.shared.libraryRestoration
            return Restoration(accountID: state.accountID, status: state.status)
        }, openScan: { id in
            AppDIContainer.shared.appRouteCoordinator.request(.scan(scanId: id), source: .internalUserAction)
        }, openLibrary: {
            AppDIContainer.shared.appRouteCoordinator.request(.scansLibrary, source: .internalUserAction)
        }, retryScan: { id in
            _ = OfflineQueueManager.shared.retryQueuedScanNow(scanId: id)
        }, retrySynchronization: {
            await OfflineJobScheduler.shared.drainRunnableJobs(using: .shared)
            if let context = OfflineQueueManager.shared.modelContext {
                await SpeciesPreferredNameRepository.syncCloudPreferences(modelContext: context, force: true)
                await ScanRepository.shared.syncHistoricalScansDown(modelContext: context)
            }
        })
    }
}
