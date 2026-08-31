import SwiftData

@MainActor
struct QueuedContentDependencies {
    let scheduleNextPersistedWake: @MainActor (
        _ queueManager: OfflineQueueManager
    ) -> Void
    let retryQueuedScanNow: @MainActor (
        _ queueManager: OfflineQueueManager,
        _ scanID: String
    ) -> Bool
    let loadQueuedContext: @MainActor (
        _ modelContainer: ModelContainer,
        _ scanID: String
    ) -> QueuedScanContext?
    let publishScanLibraryChanged: @MainActor () -> Void
    let selectionFeedback: @MainActor () -> Void
    let errorFeedback: @MainActor () -> Void

    init(
        scheduleNextPersistedWake: @escaping @MainActor (
            _ queueManager: OfflineQueueManager
        ) -> Void = { _ in },
        retryQueuedScanNow: @escaping @MainActor (
            _ queueManager: OfflineQueueManager,
            _ scanID: String
        ) -> Bool = { _, _ in false },
        loadQueuedContext: @escaping @MainActor (
            _ modelContainer: ModelContainer,
            _ scanID: String
        ) -> QueuedScanContext? = { _, _ in nil },
        publishScanLibraryChanged: @escaping @MainActor () -> Void = {},
        selectionFeedback: @escaping @MainActor () -> Void = {},
        errorFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.scheduleNextPersistedWake = scheduleNextPersistedWake
        self.retryQueuedScanNow = retryQueuedScanNow
        self.loadQueuedContext = loadQueuedContext
        self.publishScanLibraryChanged = publishScanLibraryChanged
        self.selectionFeedback = selectionFeedback
        self.errorFeedback = errorFeedback
    }

    static var live: Self {
        let container = AppDIContainer.shared
        let hapticManager = container.hapticManager
        return Self(
            scheduleNextPersistedWake: { queueManager in
                OfflineJobScheduler.shared.scheduleNextPersistedWake(
                    using: queueManager
                )
            },
            retryQueuedScanNow: { queueManager, scanID in
                queueManager.retryQueuedScanNow(scanId: scanID)
            },
            loadQueuedContext: { modelContainer, scanID in
                let readContext = ModelContext(modelContainer)
                var descriptor = FetchDescriptor<OfflineQueuedScan>(
                    predicate: #Predicate { $0.id == scanID }
                )
                descriptor.fetchLimit = 1
                guard let scan = try? readContext.fetch(descriptor).first else {
                    return nil
                }
                return QueuedScanContext(from: scan)
            },
            publishScanLibraryChanged: {
                container.appEventPublisher.send(.scanLibraryChanged)
            },
            selectionFeedback: {
                hapticManager.triggerSelectionPulse()
            },
            errorFeedback: {
                hapticManager.triggerErrorThump()
            }
        )
    }

    #if DEBUG
    static var previewQueueManager: OfflineQueueManager {
        OfflineQueueManager.shared
    }
    #endif
}
