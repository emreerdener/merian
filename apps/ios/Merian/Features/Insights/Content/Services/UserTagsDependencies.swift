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
        let cloudSyncCoordinator = UserTagsCloudSyncCoordinator { request in
            await syncTagsToCloud(request, using: manager)
        }
        return Self(
            persistMutation: { modelContext, logContext in
                do {
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
            syncToCloud: { scanID, tags in
                guard manager.isAuthenticated,
                      let expectedUserID = manager.currentUser?.id else {
                    return
                }
                cloudSyncCoordinator.enqueue(
                    UserTagsCloudSyncCoordinator.Request(
                        scanID: scanID,
                        tags: tags,
                        expectedUserID: expectedUserID
                    )
                )
            },
            publishSearchInvalidation: { scanID in
                container.appEventPublisher.send(
                    .scanSearchIndexInvalidated(scanId: scanID)
                )
            }
        )
    }

    private static func syncTagsToCloud(
        _ request: UserTagsCloudSyncCoordinator.Request,
        using manager: SupabaseManager
    ) async {
        guard let accountWorkLease = try? manager
            .beginUnownedAccountBoundWork(
                expectedUserID: request.expectedUserID
            ) else {
            return
        }
        defer {
            manager.finishAccountBoundWork(accountWorkLease)
        }

        do {
            try await manager.client
                .rpc(
                    "update_owned_scan_custom_tags",
                    params: TagSyncRPCParameters(
                        p_scan_id: request.scanID,
                        p_custom_tags: request.tags
                    )
                )
                .execute()
            guard manager.isAccountBoundWorkLeaseCurrent(
                accountWorkLease
            ) else {
                return
            }
        } catch {
            MerianLog.data.error(
                "UserTagsViewModel: failed to sync tags to cloud; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }
}

private struct TagSyncRPCParameters: Encodable, Sendable {
    let p_scan_id: String
    let p_custom_tags: [String]
}
