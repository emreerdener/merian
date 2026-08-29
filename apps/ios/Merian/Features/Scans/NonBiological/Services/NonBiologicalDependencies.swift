import SwiftData

@MainActor
struct NonBiologicalDependencies {
    let purgeExpired: @MainActor (_ modelContainer: ModelContainer) async -> Void
    let deleteRecords: @MainActor (
        _ snapshots: [NonBiologicalScanErasureSnapshot],
        _ modelContainer: ModelContainer
    ) async throws -> [String]
    let deleteFiles: @MainActor (_ paths: [String]) async -> Void
    let sendLibraryChanged: @MainActor () -> Void
    let enqueueDeletionSync: @MainActor () -> Void
    let requestRoute: @MainActor (_ route: AppRoute) -> Void
    let triggerSelectionFeedback: @MainActor () -> Void
    let triggerSuccessFeedback: @MainActor () -> Void
    let triggerErrorFeedback: @MainActor () -> Void

    init(
        purgeExpired: @escaping @MainActor (
            _ modelContainer: ModelContainer
        ) async -> Void = { _ in },
        deleteRecords: @escaping @MainActor (
            _ snapshots: [NonBiologicalScanErasureSnapshot],
            _ modelContainer: ModelContainer
        ) async throws -> [String] = { _, _ in [] },
        deleteFiles: @escaping @MainActor (_ paths: [String]) async -> Void = { _ in },
        sendLibraryChanged: @escaping @MainActor () -> Void = {},
        enqueueDeletionSync: @escaping @MainActor () -> Void = {},
        requestRoute: @escaping @MainActor (_ route: AppRoute) -> Void = { _ in },
        triggerSelectionFeedback: @escaping @MainActor () -> Void = {},
        triggerSuccessFeedback: @escaping @MainActor () -> Void = {},
        triggerErrorFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.purgeExpired = purgeExpired
        self.deleteRecords = deleteRecords
        self.deleteFiles = deleteFiles
        self.sendLibraryChanged = sendLibraryChanged
        self.enqueueDeletionSync = enqueueDeletionSync
        self.requestRoute = requestRoute
        self.triggerSelectionFeedback = triggerSelectionFeedback
        self.triggerSuccessFeedback = triggerSuccessFeedback
        self.triggerErrorFeedback = triggerErrorFeedback
    }

    static var live: Self {
        let container = AppDIContainer.shared

        return Self(
            purgeExpired: { modelContainer in
                await container.scanRepository
                    .purgeExpiredNonBiologicalScans(
                        modelContainer: modelContainer
                    )
            },
            deleteRecords: { snapshots, modelContainer in
                let actor = BackgroundDatabaseActor(
                    modelContainer: modelContainer
                )
                let payloads = snapshots.map {
                    BackgroundDatabaseActor.ScanErasurePayload(
                        id: $0.id,
                        imagePaths: $0.mediaPaths
                    )
                }
                return try await actor.bulkDeleteNonBiologicalScans(
                    payloads: payloads
                )
            },
            deleteFiles: { paths in
                await FileIOActor.shared.deleteImages(at: paths)
            },
            sendLibraryChanged: {
                container.appEventPublisher.send(.scanLibraryChanged)
            },
            enqueueDeletionSync: {
                Task {
                    await container.offlineQueueManager
                        .syncPendingDeletions()
                }
            },
            requestRoute: { route in
                container.appRouteCoordinator.request(
                    route,
                    source: .internalUserAction
                )
            },
            triggerSelectionFeedback: {
                container.hapticManager.triggerSelectionPulse()
            },
            triggerSuccessFeedback: {
                container.hapticManager.triggerSuccessPulse()
            },
            triggerErrorFeedback: {
                container.hapticManager.triggerErrorThump()
            }
        )
    }
}
