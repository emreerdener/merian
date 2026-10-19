import Foundation
import SwiftData

/// Bounded materialization on the supported iOS 17.2 store. Unique scalar
/// constraints express identity; no optimizer or constant-time guarantee is made.
/// These lookups alone grant no admission, file access or cleanup authority.
@MainActor
enum SharedMediaConsumerLookup {
    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaConsumerRecord? {
        var query = FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2; query.includePendingChanges = true
        return try unique(context.fetch(query))
    }

    static func one(_ context: ModelContext, packageID: UUID) throws -> SharedMediaConsumerRecord? {
        var query = FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate { $0.packageID == packageID })
        query.fetchLimit = 2; query.includePendingChanges = true
        return try unique(context.fetch(query))
    }

    static func page(_ context: ModelContext, after cursor: String?) throws -> [SharedMediaConsumerRecord] {
        let lower = cursor ?? ""
        if let cursor { try canonical(cursor) }
        var query = FetchDescriptor<SharedMediaConsumerRecord>(
            predicate: #Predicate { $0.cursorKey > lower }, sortBy: [SortDescriptor(\.cursorKey, comparator: .lexical)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        let rows = try context.fetch(query)
        for row in rows { try validateKey(row) }
        return rows
    }

    static func pendingPackages(_ context: ModelContext) throws -> [PhotoPreparationRecord] {
        var query = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.accountingTierRaw == "pending" })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        let rows = try context.fetch(query)
        guard rows.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        return rows
    }

    private static func unique(_ rows: [SharedMediaConsumerRecord]) throws -> SharedMediaConsumerRecord? {
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        if let row = rows.first { try validateKey(row) }
        return rows.first
    }

    private static func validateKey(_ row: SharedMediaConsumerRecord) throws {
        guard row.cursorKey == row.id.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
    }

    private static func canonical(_ value: String) throws {
        guard let id = UUID(uuidString: value), value == id.uuidString.lowercased() else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}
