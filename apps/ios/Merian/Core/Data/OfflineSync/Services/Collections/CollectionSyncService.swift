import Foundation
import SwiftData

/// Runs one collection snapshot, remote replacement, and local tombstone
/// commit inside a single account-work lease.
struct CollectionSyncService: Sendable {
    struct Dependencies: Sendable {
        let beginAccountWork:
            @Sendable () async throws -> AccountBoundWorkLease
        let isAccountWorkCurrent:
            @Sendable (AccountBoundWorkLease) async -> Bool
        let finishAccountWork:
            @Sendable (AccountBoundWorkLease) async -> Void
        let pushSnapshots:
            @Sendable ([CollectionSyncSnapshot]) async throws -> Void

        static let live = Dependencies(
            beginAccountWork: {
                let manager = await SupabaseManager.shared
                return try await manager.beginUnownedAccountBoundWork()
            },
            isAccountWorkCurrent: { lease in
                let manager = await SupabaseManager.shared
                return await manager.isAccountBoundWorkLeaseCurrent(lease)
            },
            finishAccountWork: { lease in
                let manager = await SupabaseManager.shared
                await manager.finishAccountBoundWork(lease)
            },
            pushSnapshots: { snapshots in
                try await MerianNetworkClient.shared.syncCollections(snapshots)
            }
        )
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func sync(modelContainer: ModelContainer) async -> Bool {
        let lease: AccountBoundWorkLease
        do {
            lease = try await dependencies.beginAccountWork()
        } catch {
            return false
        }

        let result = await sync(modelContainer: modelContainer, lease: lease)
        await dependencies.finishAccountWork(lease)
        return result
    }

    private func sync(
        modelContainer: ModelContainer,
        lease: AccountBoundWorkLease
    ) async -> Bool {
        do {
            try Task.checkCancellation()
            let snapshotActor = BackgroundDatabaseActor(
                modelContainer: modelContainer
            )
            let snapshots = try await snapshotActor.collectionSyncSnapshots()
            guard await dependencies.isAccountWorkCurrent(lease) else {
                return false
            }
            try await dependencies.pushSnapshots(snapshots)
            try Task.checkCancellation()
            guard await dependencies.isAccountWorkCurrent(lease) else {
                return false
            }

            let tombstoneIDs = snapshots
                .filter(\.isPendingDeletion)
                .map(\.id)
            let commitActor = BackgroundDatabaseActor(
                modelContainer: modelContainer
            )
            let purgedCount = try await commitActor
                .purgeSyncedCollectionTombstones(ids: tombstoneIDs)
            MerianLog.data.debug(
                "Collection sync completed; count=\(snapshots.count, privacy: .public) tombstonesPurged=\(purgedCount, privacy: .public)"
            )
            return true
        } catch {
            MerianLog.data.error(
                "Collection sync failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }
}
