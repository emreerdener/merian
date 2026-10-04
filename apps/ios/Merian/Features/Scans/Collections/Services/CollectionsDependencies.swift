import Combine
import SwiftData

@MainActor
struct CollectionsDependencies {
    var allowsMutation: @MainActor () -> Bool = { true }
    let events: AnyPublisher<AppEvent, Never>
    let sharedPostID: @MainActor (_ scanID: String) -> String?
    let save: @MainActor (_ modelContext: ModelContext) throws -> Void
    let rollback: @MainActor (_ modelContext: ModelContext) -> Void
    let sendLibraryChanged: @MainActor () -> Void
    let enqueueCollectionSync: @MainActor () -> Void
    let triggerSuccessFeedback: @MainActor () -> Void
    let triggerErrorFeedback: @MainActor () -> Void
    let triggerLightFeedback: @MainActor () -> Void

    init(
        events: AnyPublisher<AppEvent, Never> = Empty().eraseToAnyPublisher(),
        sharedPostID: @escaping @MainActor (_ scanID: String) -> String? = { _ in nil },
        save: @escaping @MainActor (_ modelContext: ModelContext) throws -> Void = {
            try $0.save()
        },
        rollback: @escaping @MainActor (_ modelContext: ModelContext) -> Void = {
            $0.rollback()
        },
        sendLibraryChanged: @escaping @MainActor () -> Void = {},
        enqueueCollectionSync: @escaping @MainActor () -> Void = {},
        triggerSuccessFeedback: @escaping @MainActor () -> Void = {},
        triggerErrorFeedback: @escaping @MainActor () -> Void = {},
        triggerLightFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.events = events
        self.sharedPostID = sharedPostID
        self.save = save
        self.rollback = rollback
        self.sendLibraryChanged = sendLibraryChanged
        self.enqueueCollectionSync = enqueueCollectionSync
        self.triggerSuccessFeedback = triggerSuccessFeedback
        self.triggerErrorFeedback = triggerErrorFeedback
        self.triggerLightFeedback = triggerLightFeedback
    }

    static var live: Self {
        let container = AppDIContainer.shared
        var dependencies = Self(
            events: container.appEventPublisher.publisher,
            sharedPostID: { scanID in
                ExploreShareStateStore.sharedPostId(for: scanID)
            },
            save: { modelContext in
                guard let owner = container.supabaseManager.currentUser?.id else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                for record in modelContext.changedModelsArray.compactMap({ $0 as? LocalScanRecord }) {
                    try LibraryDetailsSyncService.stage(record, ownerID: owner, context: modelContext)
                }
                try modelContext.save()
            },
            rollback: { modelContext in
                modelContext.rollback()
            },
            sendLibraryChanged: {
                container.appEventPublisher.send(.scanLibraryChanged)
            },
            enqueueCollectionSync: {
                OfflineQueueManager.shared.enqueueCollectionSync()
                if let context = OfflineQueueManager.shared.modelContext {
                    Task { await LibraryDetailsSyncService.drain(context: context, manager: .shared) }
                }
            },
            triggerSuccessFeedback: {
                container.hapticManager.triggerSuccessPulse()
            },
            triggerErrorFeedback: {
                container.hapticManager.triggerErrorThump()
            },
            triggerLightFeedback: {
                container.hapticManager.triggerLightImpact()
            }
        )
        dependencies.allowsMutation = { container.supabaseManager.allowsLocalLibraryMutation }
        return dependencies
    }
}
