import Foundation
import SwiftData

/// Pure bootstrap facts. No grant, context/model escape, filesystem access or
/// mutation. The sealed bootstrap authority validates its capability around each call.
@MainActor
enum SharedMediaNativeBootstrapDatabase {
    static func initialSnapshot(_ container: ModelContainer, inventoryID: UUID, rootBinding: String,
                                storeIdentity: String, generation: UUID) throws -> SharedMediaStorageSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = inventoryID
        let row = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        let bootstrap = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == id }))
        guard row.rootIdentity == rootBinding, row.storeIdentity == storeIdentity, row.generation == generation,
              row.modeRaw == SharedMediaNativeAppProfile.mode, row.phaseRaw == SharedMediaNativeAppProfile.phase,
              row.revision == 0, row.cursor.isEmpty, bootstrap.contractVersion == 2, bootstrap.revision == 0,
              bootstrap.inventoryGeneration == generation else { throw SharedMediaStorageFailure.conflict }
        return .init(generation: generation, revision: 0, phase: row.phaseRaw, cursor: "")
    }

    static func requireUnassociated(_ container: ModelContainer) throws {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false
        for type in CurrentSchema.models where SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(type))
            || SharedMediaStorageLookup.inboxTypes.contains(ObjectIdentifier(type)) {
            guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
        }
    }

    /// Bounded persisted identity selection; filesystem validation remains with
    /// the existing bootstrap/open path under the transferred descriptor locks.
    static func discoveryProfile(_ container: ModelContainer, inventoryID: UUID, ownerID: UUID,
                                 storeIdentity: String) throws -> SharedMediaNativeAppProfile? {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false
        var query = FetchDescriptor<SharedMediaInventoryRecord>(); query.fetchLimit = 2
        let rows = try context.fetch(query)
        if rows.isEmpty { try requireUnassociated(container); return nil }
        guard rows.count == 1, rows[0].id == inventoryID else { throw SharedMediaStorageFailure.conflict }
        let profile = try SharedMediaNativeAppEligibility.identity(container: container, inventoryID: inventoryID, ownerID: ownerID)
        try validate(container, inventoryID: inventoryID, ownerID: ownerID, storeIdentity: storeIdentity,
                     existingProfile: profile, expectedProfile: profile)
        return profile
    }

    static func validate(_ container: ModelContainer, inventoryID: UUID, ownerID: UUID, storeIdentity: String,
                         existingProfile: SharedMediaNativeAppProfile?, expectedProfile: SharedMediaNativeAppProfile?) throws {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false
        if let existingProfile {
            let id = inventoryID
            let row = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            let saved = try SharedMediaNativeAppEligibility.profile(row)
            guard saved == existingProfile, saved.ownerID == ownerID, saved.storeIdentity == storeIdentity,
                  expectedProfile == nil || saved == expectedProfile else { throw SharedMediaStorageFailure.conflict }
            _ = try SharedMediaNativeAppEligibility.header(context: context, scope: .init(inventoryID: inventoryID,
                generation: saved.generation, ownerID: ownerID, storeIdentity: storeIdentity, rootBinding: try saved.rootIdentity))
            return
        }
        var query = FetchDescriptor<SharedMediaInventoryRecord>(); query.fetchLimit = 2
        var bootstrapQuery = FetchDescriptor<SharedMediaMembershipBootstrapRecord>(); bootstrapQuery.fetchLimit = 2
        let inventories = try context.fetch(query), bootstraps = try context.fetch(bootstrapQuery)
        if inventories.isEmpty && bootstraps.isEmpty { try requireUnassociated(container); return }
        guard inventories.count == 1, bootstraps.count == 1, let row = inventories.first, let bootstrap = bootstraps.first,
              row.id == inventoryID, row.storeIdentity == storeIdentity, row.modeRaw == SharedMediaNativeAppProfile.mode,
              row.phaseRaw == SharedMediaNativeAppProfile.phase, row.cursor.isEmpty, row.revision == 0,
              bootstrap.id == inventoryID, bootstrap.inventoryGeneration == row.generation,
              bootstrap.contractVersion == 2, bootstrap.revision == 0 else { throw SharedMediaStorageFailure.conflict }
        if let expectedProfile {
            guard row.generation == expectedProfile.generation, row.rootIdentity == (try expectedProfile.rootIdentity) else { throw SharedMediaStorageFailure.conflict }
        }
        // Initialization can only associate an empty native graph. Populated V2
        // opening selects existingProfile explicitly and cannot initialize it.
        for type in CurrentSchema.models where (SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(type))
            || SharedMediaStorageLookup.inboxTypes.contains(ObjectIdentifier(type)))
            && ObjectIdentifier(type) != ObjectIdentifier(SharedMediaInventoryRecord.self)
            && ObjectIdentifier(type) != ObjectIdentifier(SharedMediaMembershipBootstrapRecord.self) {
            guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
        }
    }
}
