import Foundation
import SwiftData

/// Persisted identity assertion only. It is not a grant or a bootstrap request.
struct SharedMediaNativeScopeIdentity: Equatable, Sendable {
    let inventoryID: UUID
    let generation: UUID
    let ownerID: UUID
    let storeIdentity: String
    let rootBinding: String
    @MainActor var binding: Data {
        get throws { try JSONEncoder().encode([SharedMediaNativeScopedEligibility.mode,
            inventoryID.uuidString, storeIdentity, rootBinding]) }
    }
}

/// Separate, strict read-only profile. Qualification formats are never converted.
@MainActor
enum SharedMediaNativeScopedEligibility {
    static let mode = "nativeAppContainerV1"
    static let phase = "readyNativeAppContainerV1"

    static func requireProfile(_ inventory: SharedMediaInventoryRecord) throws {
        guard inventory.modeRaw == mode, inventory.phaseRaw == phase,
              inventory.cursor.isEmpty, inventory.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
    }

    static func requireRoots(authority: URL, photo: URL, inbox: URL) throws {
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let roots = [authority, photo, inbox]
        guard Set(roots.map { $0.standardizedFileURL }).count == 3 else { throw SharedMediaStorageFailure.invalid }
        for root in roots {
            let components = root.standardizedFileURL.pathComponents
            guard root.isFileURL, components.count > support.count, components.starts(with: support),
                  root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
                throw SharedMediaStorageFailure.invalid
            }
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
            guard values.isDirectory == true, values.isExcludedFromBackup == true else {
                throw SharedMediaStorageFailure.conflict
            }
            _ = try SharedMediaStorageFileOwner.directoryIdentity(root)
        }
    }

    /// Preflight produces no authority; the fenced constructor rechecks every fact.
    static func identity(container: ModelContainer, inventoryID: UUID, ownerID: UUID,
                         authority: URL, photo: URL, inbox: URL) throws -> SharedMediaNativeScopeIdentity {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try requireRoots(authority: authority, photo: photo, inbox: inbox)
        let store = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        let binding = try SharedMediaStorageLookup.binding(authority: SharedMediaStorageFileOwner.directoryIdentity(authority),
            sources: [SharedMediaPhotoLedger.namespace: photo, SharedMediaInboxFiles.namespace: inbox])
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let value = SharedMediaNativeScopeIdentity(inventoryID: inventoryID, generation: row.generation,
            ownerID: ownerID, storeIdentity: store, rootBinding: binding)
        _ = try header(context: context, scope: value)
        return value
    }

    static func header(context: ModelContext, scope: SharedMediaNativeScopeIdentity) throws -> SharedMediaInventoryRecord {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let id = scope.inventoryID
        let row = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        try requireProfile(row)
        let bootstrap = try one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == id }))
        guard row.generation == scope.generation, row.storeIdentity == scope.storeIdentity,
              row.rootIdentity == scope.rootBinding, bootstrap.inventoryGeneration == row.generation,
              bootstrap.contractVersion == 1, bootstrap.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
        return row
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
