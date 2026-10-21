import Foundation
import SwiftData

/// Read-only format selection, never a file, mutation or account capability.
/// The existing V1 entry remains strict; V2 is always selected explicitly.
@MainActor
enum SharedMediaNativeScopedFormat: Sendable {
    case existingV1, appV2
    var phase: String { self == .existingV1 ? SharedMediaNativeScopedEligibility.phase : SharedMediaNativeAppProfile.phase }
    var membershipVersion: Int { self == .existingV1 ? 1 : 2 }

    @MainActor func requireProfile(_ inventory: SharedMediaInventoryRecord) throws {
        switch self {
        case .existingV1: try SharedMediaNativeScopedEligibility.requireProfile(inventory)
        case .appV2: _ = try SharedMediaNativeAppEligibility.profile(inventory)
        }
    }
    @MainActor func header(context: ModelContext, scope: SharedMediaNativeScopeIdentity) throws -> SharedMediaInventoryRecord {
        switch self {
        case .existingV1: return try SharedMediaNativeScopedEligibility.header(context: context, scope: scope)
        case .appV2: return try SharedMediaNativeAppEligibility.header(context: context, scope: scope)
        }
    }
}

/// Pure persisted V2 facts. Filesystem journal, marker and held descriptor
/// verification remain mandatory in the sealed repository opener.
@MainActor
enum SharedMediaNativeAppEligibility {
    struct Header: Codable, Equatable, Sendable {
        let inventory: SharedMediaStorageSnapshot
        let bootstrapID: UUID
        let bootstrapGeneration: UUID
        let bootstrapContract: Int
        let bootstrapRevision: Int64
    }

    static func snapshot(context: ModelContext, scope: SharedMediaNativeScopeIdentity) throws -> Header {
        let row = try header(context: context, scope: scope), id = scope.inventoryID
        let bootstrap = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == id }))
        return .init(inventory: .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor),
            bootstrapID: bootstrap.id, bootstrapGeneration: bootstrap.inventoryGeneration,
            bootstrapContract: bootstrap.contractVersion, bootstrapRevision: bootstrap.revision)
    }

    static func profile(_ inventory: SharedMediaInventoryRecord) throws -> SharedMediaNativeAppProfile {
        guard inventory.modeRaw == SharedMediaNativeAppProfile.mode,
              inventory.phaseRaw == SharedMediaNativeAppProfile.phase,
              inventory.revision >= 0, inventory.cursor.isEmpty else { throw SharedMediaStorageFailure.conflict }
        let bytes = Data(inventory.rootIdentity.utf8)
        let fields = try SharedMediaNativeBootstrapCodec.decode([String].self, bytes)
        guard fields.count == 7, fields[0] == SharedMediaNativeAppProfile.mode,
              let owner = UUID(uuidString: fields[1]), owner.uuidString == fields[1],
              fields[2] == inventory.id.uuidString, fields[3] == inventory.generation.uuidString,
              fields[4] == inventory.storeIdentity, UUID(uuidString: fields[4]) != nil,
              [fields[5], fields[6]].allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) else {
            throw SharedMediaStorageFailure.conflict
        }
        let value = SharedMediaNativeAppProfile(ownerID: owner, inventoryID: inventory.id, generation: inventory.generation,
            storeIdentity: inventory.storeIdentity, physicalBinding: fields[5], receiptDigest: fields[6])
        guard try value.binding == bytes else { throw SharedMediaStorageFailure.conflict }; return value
    }

    static func identity(container: ModelContainer, inventoryID: UUID, ownerID: UUID) throws -> SharedMediaNativeAppProfile {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let result = try profile(row)
        guard result.ownerID == ownerID, result.storeIdentity == (try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)) else { throw SharedMediaStorageFailure.conflict }
        _ = try header(context: context, scope: .init(inventoryID: inventoryID, generation: result.generation,
            ownerID: ownerID, storeIdentity: result.storeIdentity, rootBinding: try result.rootIdentity))
        return result
    }

    static func header(context: ModelContext, scope: SharedMediaNativeScopeIdentity) throws -> SharedMediaInventoryRecord {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let id = scope.inventoryID
        let row = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        let profile = try profile(row)
        let bootstrap = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == id }))
        guard profile.ownerID == scope.ownerID, row.generation == scope.generation,
              row.storeIdentity == scope.storeIdentity, row.rootIdentity == scope.rootBinding,
              bootstrap.inventoryGeneration == scope.generation, bootstrap.contractVersion == 2,
              bootstrap.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
