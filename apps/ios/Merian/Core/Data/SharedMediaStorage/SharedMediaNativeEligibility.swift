import CoreData
import Foundation
import SwiftData

/// Read-only admission validation. It grants no store, file or mutation authority.
@MainActor
enum SharedMediaNativeEligibility {
    static func requireTopology(storeURL: URL, authorityRoot: URL, photoRoot: URL, inboxRoot: URL) throws {
        let parent = authorityRoot.standardizedFileURL.deletingLastPathComponent()
        guard photoRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              inboxRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              storeURL.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent() == parent,
              [authorityRoot, photoRoot, inboxRoot, storeURL, storeURL.deletingLastPathComponent()].allSatisfy(fixtureLocation) else {
            throw SharedMediaStorageFailure.invalid
        }
    }

    static func storeIdentity(at url: URL) throws -> String {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        guard let identity = metadata[NSStoreUUIDKey] as? String, UUID(uuidString: identity) != nil else {
            throw SharedMediaStorageFailure.conflict
        }
        return identity
    }

    /// Unknown fixture-root content is never adopted, cleared or converted.
    static func requireEmptyBootstrapRoots(_ roots: [URL]) throws {
        for root in roots {
            guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else { throw SharedMediaStorageFailure.conflict }
        }
    }

    static func requireOnlyPhotoNamespace(_ root: URL?) throws {
        guard let root, try FileManager.default.contentsOfDirectory(atPath: root.path) == ["PhotoPreparation"] else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    static func requireOriginalAccount(_ context: ModelContext, ownerID: UUID) throws {
        // Full and stripped terminal receipts both retain their account identity.
        // Package ownership also covers empty drafts without an acquisition row.
        guard try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.ownerID != ownerID })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.ownerID != ownerID })) == 0 else {
            throw PhotoPreparationFailure.accountChanged
        }
    }

    static func originalState(_ context: ModelContext, inventoryID: UUID,
                                      storeIdentity: String, rootBinding: String) throws -> SharedMediaInventoryRecord? {
        if try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0 {
            return try emptyState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding)
        }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        var query = FetchDescriptor<SharedMediaInventoryRecord>(); query.fetchLimit = 2
        var bootstrap = FetchDescriptor<SharedMediaMembershipBootstrapRecord>(); bootstrap.fetchLimit = 2
        let rows = try context.fetch(query), receipts = try context.fetch(bootstrap)
        guard rows.count == 1, let row = rows.first, row.id == inventoryID,
              row.storeIdentity == storeIdentity, row.rootIdentity == rootBinding,
              receipts.count == 1, let receipt = receipts.first, receipt.id == inventoryID,
              receipt.inventoryGeneration == row.generation, receipt.contractVersion == 1, receipt.revision == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        return row
    }

    static func fixtureLocation(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return ![URL.documentsDirectory, URL.applicationSupportDirectory].contains {
            path.starts(with: $0.resolvingSymlinksInPath().standardizedFileURL.pathComponents)
        }
    }

    /// Full zero-state inventory is deliberate until native operations exist.
    /// Never infer bootstrap metadata from a surviving graph or root marker.
    static func emptyState(_ context: ModelContext, inventoryID: UUID,
                                   storeIdentity: String, rootBinding: String) throws -> SharedMediaInventoryRecord? {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for type in CurrentSchema.models where ObjectIdentifier(type) != ObjectIdentifier(SharedMediaInventoryRecord.self)
            && ObjectIdentifier(type) != ObjectIdentifier(SharedMediaMembershipBootstrapRecord.self) {
            guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.closed }
        }
        var inventories = FetchDescriptor<SharedMediaInventoryRecord>(); inventories.fetchLimit = 2
        var receipts = FetchDescriptor<SharedMediaMembershipBootstrapRecord>(); receipts.fetchLimit = 2
        let rows = try context.fetch(inventories), bootstraps = try context.fetch(receipts)
        if rows.isEmpty && bootstraps.isEmpty { return nil }
        guard rows.count == 1, bootstraps.count == 1, let row = rows.first, let receipt = bootstraps.first,
              row.id == inventoryID, row.modeRaw == "nativeQualificationV1", row.phaseRaw == "readyNativeAccountingV1", row.cursor.isEmpty,
              row.storeIdentity == storeIdentity, row.rootIdentity == rootBinding, row.revision == 0,
              receipt.id == inventoryID, receipt.inventoryGeneration == row.generation,
              receipt.contractVersion == 1, receipt.revision == 0 else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
