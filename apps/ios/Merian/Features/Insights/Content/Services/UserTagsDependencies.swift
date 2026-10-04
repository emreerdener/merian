import Foundation
import SwiftData

@MainActor
struct UserTagsDependencies {
    let persistMutation: @MainActor (
        _ modelContext: ModelContext,
        _ logContext: String
    ) -> Bool
    let syncToCloud: @MainActor (
        _ scanID: String,
        _ tags: [String]
    ) -> Void
    let publishSearchInvalidation: @MainActor (_ scanID: String) -> Void

    init(
        persistMutation: @escaping @MainActor (
            _ modelContext: ModelContext,
            _ logContext: String
        ) -> Bool = { _, _ in false },
        syncToCloud: @escaping @MainActor (
            _ scanID: String,
            _ tags: [String]
        ) -> Void = { _, _ in },
        publishSearchInvalidation: @escaping @MainActor (
            _ scanID: String
        ) -> Void = { _ in }
    ) {
        self.persistMutation = persistMutation
        self.syncToCloud = syncToCloud
        self.publishSearchInvalidation = publishSearchInvalidation
    }

    static var live: Self {
        let container = AppDIContainer.shared
        let manager = SupabaseManager.shared
        return Self(
            persistMutation: { modelContext, logContext in
                guard manager.allowsLocalLibraryMutation else { return false }
                do {
                    guard let ownerID = manager.currentUser?.id else { return false }
                    for record in modelContext.changedModelsArray.compactMap({ $0 as? LocalScanRecord }) {
                        try LibraryDetailsSyncService.stage(record, ownerID: ownerID, context: modelContext)
                    }
                    try modelContext.save()
                    return true
                } catch {
                    modelContext.rollback()
                    MerianLog.data.error(
                        "UserTagsViewModel: failed to save \(logContext, privacy: .public): \(error, privacy: .private)"
                    )
                    return false
                }
            },
            syncToCloud: { _, _ in
                guard let context = OfflineQueueManager.shared.modelContext else { return }
                Task { await LibraryDetailsSyncService.drain(context: context, manager: manager) }
            },
            publishSearchInvalidation: { scanID in
                container.appEventPublisher.send(
                    .scanSearchIndexInvalidated(scanId: scanID)
                )
            }
        )
    }

}
