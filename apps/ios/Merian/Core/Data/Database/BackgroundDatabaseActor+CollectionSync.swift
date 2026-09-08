import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    /// Projects only syncable collection rows and their direct inverse
    /// memberships. Stable ordering keeps repeated requests deterministic.
    func collectionSyncSnapshots() throws -> [CollectionSyncSnapshot] {
        var descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate { $0.name != "Favorites" },
            sortBy: [
                SortDescriptor(\.createdAt),
                SortDescriptor(\.id)
            ]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.scans]

        return try modelContext.fetch(descriptor).map { collection in
            CollectionSyncSnapshot(
                id: collection.id,
                name: collection.name,
                createdAt: collection.createdAt,
                isPendingDeletion: collection.isPendingDeletion,
                scanIDs: Array(Set((collection.scans ?? []).map(\.id)))
                    .sorted()
            )
        }
    }

    /// Purges only rows that are still tombstones at commit time. A fresh actor
    /// should own this call so a concurrent local reactivation cannot be hidden
    /// by the context that produced the outgoing snapshot.
    @discardableResult
    func purgeSyncedCollectionTombstones(ids: [String]) throws -> Int {
        guard !ids.isEmpty else { return 0 }

        let uniqueIDs = Array(Set(ids))
        let descriptor = FetchDescriptor<ScanCollection>(
            predicate: #Predicate {
                uniqueIDs.contains($0.id) && $0.isPendingDeletion
            }
        )
        let tombstones = try modelContext.fetch(descriptor)
        for tombstone in tombstones {
            modelContext.delete(tombstone)
        }
        guard !tombstones.isEmpty else { return 0 }

        do {
            try modelContext.save()
            return tombstones.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
