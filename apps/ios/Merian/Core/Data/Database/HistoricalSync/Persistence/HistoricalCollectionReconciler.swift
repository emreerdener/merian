import Foundation
import SwiftData

/// Synchronous persistence helper. The calling ModelActor retains isolation and
/// owns rollback; no context or model leaves that invocation.
struct HistoricalCollectionReconciler {
    private let activeContext: ModelContext

    init(context: ModelContext) { activeContext = context }

    func reconcile(
        remoteCollections: [CloudCollectionResponse]
    ) throws {
        try Task.checkCancellation()
        // fetchLimit: 500 is a defensive ceiling — an unbounded full-table scan can fault orphaned
        // or schema-migrated collection records into memory before sync begins.
        var collectionsDescriptor = FetchDescriptor<ScanCollection>()
        collectionsDescriptor.fetchLimit = 500
        let existingCollections = try activeContext.fetch(
            collectionsDescriptor
        )
        // Old clients could restore a remote collection into the reserved local
        // Favorites namespace. Preserve its private favorite memberships before
        // importing that stable remote ID as an ordinary, editable collection.
        let remoteIDs = Set(remoteCollections.map { $0.id.lowercased() })
        let collidingFavorites = existingCollections.filter { $0.name == "Favorites" && remoteIDs.contains($0.id.lowercased()) }
        if !collidingFavorites.isEmpty {
            let favorite = existingCollections.first { $0.name == "Favorites" && !remoteIDs.contains($0.id.lowercased()) }
                ?? ScanCollection(name: "Favorites")
            if favorite.modelContext == nil { activeContext.insert(favorite) }
            let detailJobs = try activeContext.fetch(FetchDescriptor<OfflineJobRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.id, order: .reverse)]
            )).filter { $0.id.hasPrefix("library-details:") }
            for collision in collidingFavorites {
                for scan in collision.scans ?? [] {
                    // Ordinary legacy membership is not proof of a private favorite.
                    // Only move state represented by a restored snapshot or edit.
                    guard let proof = detailJobs.first(where: { $0.subjectId == scan.id }),
                          proof.status != .cancelled, let json = proof.metadataJSON,
                          let mutation = try? JSONDecoder().decode(LibraryDetailsSyncService.Mutation.self, from: Data(json.utf8)),
                          mutation.scanID == scan.id, mutation.isFavorite else { continue }
                    var memberships = scan.collections ?? []
                    if !memberships.contains(where: { $0.id == favorite.id }) {
                        memberships.append(favorite)
                        scan.collections = memberships
                    }
                }
            }
        }
        var existingLookup = Dictionary(existingCollections.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // Fetch only the local scan records referenced by the incoming collections.
        let referencedScanIds = remoteCollections.compactMap { $0.collection_scans }.flatMap { $0 }.map { $0.scan_id }
        let allScansDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { referencedScanIds.contains($0.id) })
        let localScans: [LocalScanRecord] = referencedScanIds.isEmpty
            ? []
            : try activeContext.fetch(allScansDescriptor)
        let localScansLookup = Dictionary(localScans.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // Read membership from the `LocalScanRecord.collections` side in bounded batches to
        // avoid faulting every `ScanCollection.scans` array or the entire scan library at once.
        let relevantCollectionIDs = Set(remoteCollections.map { $0.id.lowercased() })
        var collectionMembersByID = try fetchCollectionMembersByID(
            relevantCollectionIDs: relevantCollectionIDs,
            activeContext: activeContext
        )

        for remote in remoteCollections {
            try Task.checkCancellation()
            let col: ScanCollection
            let remoteIdLower = remote.id.lowercased()
            if let existing = existingLookup[remoteIdLower] {
                col = existing
                existingLookup.removeValue(forKey: remoteIdLower)

                // --- INBOUND SHIELD ---
                // If a collection is marked as deleted locally, aggressively ignore any remote
                // representations of it. This prevents an obsolete or delayed remote state
                // from "resurrecting" the collection locally or wiping its tombstone status.
                if existing.isPendingDeletion {
                    continue
                }
            } else {
                col = ScanCollection(name: remote.name)
                col.id = remote.id
                if let parsedDate = DateUtilities.iso8601FractionalFormatter.date(from: remote.created_at) ?? DateUtilities.iso8601Formatter.date(from: remote.created_at) {
                    col.createdAt = parsedDate
                }
                activeContext.insert(col)
            }

            col.name = restoredCollectionName(remote.name, id: remote.id)

            let remoteScanIds = Set(remote.collection_scans?.map { $0.scan_id } ?? [])

            // Remove local scans that are NOT in the remote list,
            // EXCEPT for those that are still pending upload (offline captures).
            // A reliable heuristic: if the image path is local (doesn't start with http/https), it hasn't synced yet.
            let currentScans = collectionMembersByID[remoteIdLower] ?? []
            for scan in currentScans where !remoteScanIds.contains(scan.id) {
                let isSynced = scan.coverImagePath?.starts(with: "http") == true || scan.coverImagePath?.starts(with: "https") == true || scan.coverImagePath == nil
                if isSynced {
                    // Drive the removal from the inverse side via reassignment — in-place
                    // mutation on optional SwiftData arrays can fail to notify the context.
                    var updatedCollections = scan.collections ?? []
                    let originalCount = updatedCollections.count
                    updatedCollections.removeAll(where: { $0.id == col.id })
                    if updatedCollections.count != originalCount {
                        scan.collections = updatedCollections
                    }
                }
            }

            if let scans = remote.collection_scans {
                for scanMapping in scans {
                    if let localScan = localScansLookup[scanMapping.scan_id.lowercased()] {
                        // Drive the relationship from the inverse side to avoid the static type
                        // mismatch between ScanCollection.scans ([V12.LocalScanRecord]) and
                        // the current-schema LocalScanRecord (V13). SwiftData propagates the
                        // inverse automatically.
                        var updatedCollections = localScan.collections ?? []
                        if !updatedCollections.contains(where: { $0.id == col.id }) {
                            updatedCollections.append(col)
                            localScan.collections = updatedCollections
                            collectionMembersByID[remoteIdLower, default: []].append(localScan)
                        }
                    }
                }
            }
        }

        try Task.checkCancellation()
        for (_, obsolete) in existingLookup where obsolete.name != "Favorites" {
            try Task.checkCancellation()
            activeContext.delete(obsolete)
        }

        try Task.checkCancellation()
        try activeContext.save()
    }

    private func restoredCollectionName(_ name: String, id: String) -> String {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).compare(
            "Favorites", options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame else { return name }
        // Keep the original label and stable ID, while leaving the protected
        // local-only Favorites folder as the sole owner of private favorite state.
        return "\(name.trimmingCharacters(in: .whitespacesAndNewlines)) (restored \(id.lowercased()))"
    }

    private func fetchCollectionMembersByID(
        relevantCollectionIDs: Set<String>,
        activeContext: ModelContext
    ) throws -> [String: [LocalScanRecord]] {
        guard !relevantCollectionIDs.isEmpty else { return [:] }

        let batchSize = 200
        var offset = 0
        var collectionMembersByID: [String: [LocalScanRecord]] = [:]

        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<LocalScanRecord>(
                sortBy: [SortDescriptor(\.timestamp)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            descriptor.relationshipKeyPathsForPrefetching = [\.collections]

            let batch = try activeContext.fetch(descriptor)
            guard !batch.isEmpty else { break }

            for scan in batch {
                for attachedCollection in scan.collections ?? [] {
                    let attachedID = attachedCollection.id.lowercased()
                    guard relevantCollectionIDs.contains(attachedID) else { continue }
                    collectionMembersByID[attachedID, default: []].append(scan)
                }
            }

            offset += batch.count
            if batch.count < batchSize { break }
        }

        return collectionMembersByID
    }
}
