import CryptoKit
import Foundation
import SwiftData

/// Exact bounded lookups shared by the fenced repository modes.
@MainActor
enum SharedMediaStorageLookup {
    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaAllocationRecord? {
        var query = FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaReferenceRecord? {
        var query = FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    static func one(_ context: ModelContext, id: UUID) throws -> SharedMediaLeaseRecord? {
        var query = FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }
    static func binding(authority: String, sources: [String: URL]) throws -> String {
        var parts = [authority]
        for namespace in sources.keys.sorted() {
            try SharedMediaStoragePolicy.token(namespace)
            let root = sources[namespace]!
            parts += [namespace, root.standardizedFileURL.path, try SharedMediaStorageFileOwner.directoryIdentity(root)]
        }
        return SHA256.hash(data: Data(try JSONEncoder().encode(parts))).map { String(format: "%02x", $0) }.joined()
    }

    static let inboxTypes = Set([ObjectIdentifier(SharedMediaInboxSourceRecord.self), ObjectIdentifier(SharedMediaInboxHandoffRecord.self)])

    static let photoTypes = Set([ObjectIdentifier(PhotoPreparationRecord.self),
        ObjectIdentifier(PhotoPreparationAsset.self), ObjectIdentifier(PhotoPreparationReference.self),
        ObjectIdentifier(PhotoPreparationLease.self)])

    static let ledgerTypes = Set([ObjectIdentifier(SharedMediaInventoryRecord.self),
        ObjectIdentifier(SharedMediaAllocationRecord.self), ObjectIdentifier(SharedMediaReferenceRecord.self),
        ObjectIdentifier(SharedMediaLeaseRecord.self)])

    static func count<T: PersistentModel>(_ context: ModelContext, _ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

}
