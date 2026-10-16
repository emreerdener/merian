import CoreData
import CryptoKit
import Foundation
import SwiftData

/// No live composition exists. Exclusive explicit-root lifetime + synchronous
/// fresh-context transactions serialize every instance, including across processes.
@MainActor
final class SharedMediaStorageRepository {
    private let container: ModelContainer
    private let files: SharedMediaStorageFileOwner
    private let inventoryID: UUID
    private let storeIdentity: String
    private let mode: SharedMediaStorageMode
    private let processEpoch = UUID()
    private let sources: [String: URL]
    private let rootBinding: String
    private let storeBinding: Data
    let photoFiles: PhotoPreparationLockedFiles?
    #if DEBUG
    var photoFault: ((SharedMediaPhotoBoundary) throws -> Void)?
    #endif

    init(container: ModelContainer, authorityRoot: URL, inventoryID: UUID, mode: SharedMediaStorageMode, sources: [String: URL] = [:],
         photoInspection: PhotoPreparationDirectoryInspection = .init()) throws {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly else { throw SharedMediaStorageFailure.invalid }
        self.container = container
        self.inventoryID = inventoryID
        self.mode = mode
        self.sources = sources
        guard mode != .qualification || sources.isEmpty else { throw SharedMediaStorageFailure.invalid }
        if mode == .p1Qualification {
            guard sources.count == 1, let photoRoot = sources[SharedMediaPhotoLedger.namespace],
                  photoRoot.standardizedFileURL.deletingLastPathComponent() == authorityRoot.standardizedFileURL.deletingLastPathComponent(),
                  configuration.url.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent() == authorityRoot.standardizedFileURL.deletingLastPathComponent(),
                  !photoRoot.standardizedFileURL.pathComponents.starts(with: URL.documentsDirectory.standardizedFileURL.pathComponents) else {
                throw SharedMediaStorageFailure.invalid
            }
        }
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url, sources: sources)
        try files.requireEmpty() // Authority root is separate from store/media; L1 never writes into it.
        rootBinding = try Self.binding(authority: files.identity, sources: sources)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: configuration.url)
        guard let storeUUID = metadata[NSStoreUUIDKey] as? String, UUID(uuidString: storeUUID) != nil else {
            throw SharedMediaStorageFailure.conflict
        }
        storeIdentity = storeUUID
        storeBinding = try JSONEncoder().encode(["v1", inventoryID.uuidString, storeUUID, rootBinding])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if mode != .observation {
            for type in CurrentSchema.models where !Self.ledgerTypes.contains(ObjectIdentifier(type))
                && !(mode == .p1Qualification && Self.photoTypes.contains(ObjectIdentifier(type))) {
                guard try Self.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
            }
        }
        let initializing = try !Self.hasLiabilities(in: context)
        if mode == .p1Qualification {
            if initializing {
                for type in CurrentSchema.models where Self.photoTypes.contains(ObjectIdentifier(type)) {
                    guard try Self.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
                }
            }
            photoFiles = try PhotoPreparationLockedFiles(root: sources[SharedMediaPhotoLedger.namespace]!,
                sharedBinding: SharedMediaPhotoBinding(bytes: storeBinding, initializing: initializing), inspection: photoInspection)
        } else { photoFiles = nil }
        try files.bindStore(storeBinding, initializing: initializing)
        if initializing {
            context.insert(SharedMediaInventoryRecord(id: inventoryID, rootIdentity: rootBinding,
                storeIdentity: storeIdentity, generation: UUID(), revision: 0, modeRaw: mode.rawValue,
                phaseRaw: mode == .observation ? "observing" : (mode == .qualification ? "readyQualification" : "readyP1"), cursor: ""))
            try context.save()
        }
        _ = try state()
    }

    static func hasLiabilities(in context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) > 0
    }

    func snapshot() throws -> SharedMediaStorageSnapshot {
        let (_, inventory) = try state()
        return value(inventory)
    }

    /// Bounded observations only. Cursor is progress, never a completeness assertion.
    /// No L1 API may promote observations or claim a stable whole-source snapshot.
    func observe(namespace: String, tokens: [String], cursor: String,
                 expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        guard mode == .observation, inventory.phaseRaw == "observing",
              tokens.count <= SharedMediaStoragePolicy.pageSize,
              sources[namespace] != nil,
              cursor.utf8.count <= SharedMediaStoragePolicy.maximumTokenBytes,
              Set(tokens).count == tokens.count else { throw SharedMediaStorageFailure.invalid }
        try revision(inventory, expected)
        for token in tokens {
            // Stable namespace/token ID permits exact page recovery across restart.
            let digest = Array(SHA256.hash(data: Data((namespace + "\0" + token).utf8)))
            let id = UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
            let item = try files.observe(id: id, namespace: namespace, token: token)
            try SharedMediaStoragePolicy.token(item.namespace)
            try SharedMediaStoragePolicy.token(item.token)
            guard item.bytes >= 0, !item.physicalIdentity.isEmpty,
                  item.physicalIdentity.utf8.count <= 256 else { throw SharedMediaStorageFailure.invalid }
            if let prior: SharedMediaAllocationRecord = try one(context, id: item.id) {
                guard prior.inventoryID == inventoryID, prior.poolRaw == "observed",
                      prior.namespaceRaw == item.namespace, prior.fileToken == item.token,
                      prior.materializedBytes == item.bytes, prior.physicalIdentity == item.physicalIdentity else {
                    throw SharedMediaStorageFailure.conflict
                }
            } else {
                var duplicate = false
                try visit(context, SharedMediaAllocationRecord.self) {
                    if $0.namespaceRaw == item.namespace && $0.fileToken == item.token { duplicate = true }
                }
                guard !duplicate else { throw SharedMediaStorageFailure.conflict }
                context.insert(SharedMediaAllocationRecord(id: item.id, inventoryID: inventoryID,
                    accountID: nil, packageID: nil, namespaceRaw: item.namespace, fileToken: item.token,
                    poolRaw: "observed", stateRaw: "legacyObserved", materializedBytes: item.bytes,
                    reservedBytes: 0, physicalIdentity: item.physicalIdentity))
            }
        }
        inventory.cursor = cursor
        return try save(context, inventory)
    }

    /// Retains a fixed destination reservation only. L1 has no media writer.
    func reserve(_ request: SharedMediaStorageReservation, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        try requireQualification(inventory)
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        guard request.pool != .observed, request.bytes > 0 else { throw SharedMediaStorageFailure.invalid }
        if let prior: SharedMediaAllocationRecord = try one(context, id: request.id) {
            guard prior.stateRaw == "reserved", prior.accountID == request.accountID,
                  prior.packageID == request.packageID, prior.poolRaw == request.pool.rawValue,
                  prior.reservedBytes == request.bytes else { throw SharedMediaStorageFailure.conflict }
            return value(inventory) // Exact saved reservation, never a renewed identity/allowance.
        }
        try revision(inventory, expected)
        try visit(context, SharedMediaAllocationRecord.self) {
            if $0.packageID == request.packageID && $0.accountID != request.accountID { throw SharedMediaStorageFailure.conflict }
        }
        var totals = try accounting(context)
        try totals.include(.init(packageID: request.packageID, pool: request.pool, materialized: 0, reserved: request.bytes))
        try totals.checkAvailable(files.availableBytes())
        context.insert(SharedMediaAllocationRecord(id: request.id, inventoryID: inventoryID,
            accountID: request.accountID, packageID: request.packageID, namespaceRaw: "qualification",
            fileToken: request.id.uuidString.lowercased(), poolRaw: request.pool.rawValue,
            stateRaw: "reserved", materializedBytes: 0, reservedBytes: request.bytes, physicalIdentity: nil))
        return try save(context, inventory)
    }

    func acquireReference(id: UUID, allocationID: UUID, accountID: UUID, ownerID: String,
                          role: String, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        try requireQualification(inventory)
        try SharedMediaStoragePolicy.token(ownerID)
        try SharedMediaStoragePolicy.token(role)
        let allocation = try mutableAllocation(context, allocationID)
        guard allocation.accountID == accountID else { throw SharedMediaStorageFailure.conflict }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if let prior: SharedMediaReferenceRecord = try one(context, id: id) {
            guard prior.allocationID == allocationID, prior.accountID == accountID,
                  prior.ownerID == ownerID, prior.roleRaw == role, prior.stateRaw == "live" else {
                throw SharedMediaStorageFailure.conflict
            }
            return value(inventory)
        }
        try revision(inventory, expected)
        context.insert(SharedMediaReferenceRecord(id: id, allocationID: allocationID,
            accountID: accountID, ownerID: ownerID, roleRaw: role, stateRaw: "live", revision: 0))
        return try save(context, inventory)
    }

    func releaseReference(id: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        guard mode != .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard let edge: SharedMediaReferenceRecord = try one(context, id: id) else { throw SharedMediaStorageFailure.invalid }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if edge.stateRaw == "retired" { return value(inventory) }
        try revision(inventory, expected)
        guard edge.stateRaw == "live" else { throw SharedMediaStorageFailure.conflict }
        edge.stateRaw = "retired"
        edge.revision = try SharedMediaStoragePolicy.add(edge.revision, 1)
        return try save(context, inventory)
    }

    func startLocalLease(id: UUID, allocationID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        try requireQualification(inventory)
        _ = try mutableAllocation(context, allocationID)
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if let old: SharedMediaLeaseRecord = try one(context, id: id) {
            guard old.allocationID == allocationID, old.processEpoch == processEpoch,
                  old.stateRaw == "open" else { throw SharedMediaStorageFailure.conflict }
            return value(inventory)
        }
        try revision(inventory, expected)
        context.insert(SharedMediaLeaseRecord(id: id, allocationID: allocationID, processEpoch: processEpoch,
            purposeRaw: "localQualification", stateRaw: "open"))
        return try save(context, inventory)
    }

    /// Cannot close an earlier process's lease or any background/remote work.
    func finishLocalLease(id: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        guard mode != .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard let lease: SharedMediaLeaseRecord = try one(context, id: id),
              lease.processEpoch == processEpoch, lease.purposeRaw == "localQualification" else {
            throw SharedMediaStorageFailure.conflict
        }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if lease.stateRaw == "closed" { return value(inventory) }
        try revision(inventory, expected)
        guard lease.stateRaw == "open" else { throw SharedMediaStorageFailure.inUse }
        lease.stateRaw = "closed"
        return try save(context, inventory)
    }

    func retire(allocationID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        guard mode == .qualification else { throw SharedMediaStorageFailure.closed }
        guard let allocation: SharedMediaAllocationRecord = try one(context, id: allocationID),
              allocation.poolRaw != "observed" else { throw SharedMediaStorageFailure.invalid }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if allocation.stateRaw == "retiring" { return value(inventory) }
        try revision(inventory, expected)
        _ = try mutableAllocation(context, allocationID)
        var held = false
        try visit(context, SharedMediaReferenceRecord.self) { if $0.allocationID == allocationID && $0.stateRaw != "retired" { held = true } }
        try visit(context, SharedMediaLeaseRecord.self) { if $0.allocationID == allocationID && $0.stateRaw != "closed" { held = true } }
        guard !held else { throw SharedMediaStorageFailure.inUse }
        allocation.stateRaw = "retiring" // Irreversible; bytes remain charged, no physical-release API.
        return try save(context, inventory)
    }

    /// Global admission closure only; preserves every reference, lease and charge.
    func closeAdmission(expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        guard mode != .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if inventory.phaseRaw == "retiring" { return value(inventory) }
        try revision(inventory, expected)
        inventory.phaseRaw = "retiring"
        return try save(context, inventory)
    }

    /// Local account reference retirement only, not permission to erase files or remote data.
    func retireAccountReferences(_ accountID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        guard mode != .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        try revision(inventory, expected)
        try visit(context, SharedMediaReferenceRecord.self) {
            if $0.accountID == accountID && $0.stateRaw == "live" {
                $0.stateRaw = "retired"
                $0.revision = try SharedMediaStoragePolicy.add($0.revision, 1)
            }
        }
        return try save(context, inventory)
    }

    private func state() throws -> (ModelContext, SharedMediaInventoryRecord) {
        try files.requireEmpty()
        try files.bindStore(storeBinding, initializing: false)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var query = FetchDescriptor<SharedMediaInventoryRecord>()
        query.fetchLimit = 2
        let inventories = try context.fetch(query)
        guard inventories.count == 1, let item = inventories.first,
              item.id == inventoryID, item.rootIdentity == rootBinding,
              rootBinding == (try Self.binding(authority: files.identity, sources: sources)), item.storeIdentity == storeIdentity,
              item.modeRaw == mode.rawValue, item.revision >= 0,
              (mode == .p1Qualification ? item.phaseRaw == "readyP1" :
                (mode == .qualification ? ["readyQualification", "retiring"].contains(item.phaseRaw) : ["observing", "retiring"].contains(item.phaseRaw))) else {
            throw SharedMediaStorageFailure.conflict
        }
        if mode == .p1Qualification {
            try photoFiles?.checkIdentity()
            for type in CurrentSchema.models where !Self.ledgerTypes.contains(ObjectIdentifier(type)) && !Self.photoTypes.contains(ObjectIdentifier(type)) {
                guard try Self.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
            }
        }
        _ = try accounting(context)
        return (context, item)
    }

    private func accounting(_ context: ModelContext) throws -> SharedMediaStoragePolicy.Totals {
        if mode == .p1Qualification { return try photoLedger(context).validate() }
        var totals = SharedMediaStoragePolicy.Totals()
        var packageAccounts: [UUID: UUID] = [:]
        try visit(context, SharedMediaAllocationRecord.self) { row in
            guard row.inventoryID == inventoryID, let pool = SharedMediaStoragePool(rawValue: row.poolRaw),
                  ["legacyObserved", "reserved", "retiring"].contains(row.stateRaw),
                  (pool == .observed) == (row.stateRaw == "legacyObserved"),
                  pool == .observed || row.accountID != nil else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaStoragePolicy.token(row.namespaceRaw)
            try SharedMediaStoragePolicy.token(row.fileToken)
            if pool == .observed {
                guard mode == .observation, row.accountID == nil, sources[row.namespaceRaw] != nil,
                      let identity = row.physicalIdentity, !identity.isEmpty, identity.utf8.count <= 256 else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard mode == .qualification, row.namespaceRaw == "qualification",
                      row.fileToken == row.id.uuidString.lowercased(), row.physicalIdentity == nil,
                      row.materializedBytes == 0, row.reservedBytes > 0 else { throw SharedMediaStorageFailure.conflict }
            }
            if let package = row.packageID, let account = row.accountID {
                guard packageAccounts[package].map({ $0 == account }) ?? true else { throw SharedMediaStorageFailure.conflict }
                packageAccounts[package] = account
            }
            try totals.include(.init(packageID: row.packageID, pool: pool, materialized: row.materializedBytes, reserved: row.reservedBytes))
        }
        try visit(context, SharedMediaReferenceRecord.self) { row in
            try SharedMediaStoragePolicy.token(row.ownerID)
            try SharedMediaStoragePolicy.token(row.roleRaw)
            guard let parent: SharedMediaAllocationRecord = try one(context, id: row.allocationID),
                  parent.inventoryID == inventoryID, parent.accountID == row.accountID, row.revision >= 0,
                  ["live", "retired", "observed"].contains(row.stateRaw),
                  (parent.poolRaw == "observed") == (row.stateRaw == "observed"),
                  parent.stateRaw != "retiring" || row.stateRaw == "retired" else { throw SharedMediaStorageFailure.conflict }
        }
        try visit(context, SharedMediaLeaseRecord.self) { row in
            guard let parent: SharedMediaAllocationRecord = try one(context, id: row.allocationID),
                  parent.inventoryID == inventoryID, parent.poolRaw != "observed", row.purposeRaw == "localQualification",
                  ["open", "closed", "unknown"].contains(row.stateRaw),
                  parent.stateRaw != "retiring" || row.stateRaw == "closed" else { throw SharedMediaStorageFailure.conflict }
        }
        return totals
    }

    private func mutableAllocation(_ context: ModelContext, _ id: UUID) throws -> SharedMediaAllocationRecord {
        guard let item: SharedMediaAllocationRecord = try one(context, id: id), item.stateRaw == "reserved" else {
            throw SharedMediaStorageFailure.closed
        }
        return item
    }

    private func requireQualification(_ inventory: SharedMediaInventoryRecord) throws {
        guard mode == .qualification, inventory.phaseRaw == "readyQualification" else { throw SharedMediaStorageFailure.closed }
    }

    private func revision(_ inventory: SharedMediaInventoryRecord, _ expected: SharedMediaStorageSnapshot) throws {
        guard inventory.generation == expected.generation, inventory.revision == expected.revision else { throw SharedMediaStorageFailure.stale }
    }

    private func save(_ context: ModelContext, _ inventory: SharedMediaInventoryRecord) throws -> SharedMediaStorageSnapshot {
        try files.requireEmpty()
        guard rootBinding == (try Self.binding(authority: files.identity, sources: sources)) else { throw SharedMediaStorageFailure.conflict }
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        try context.save()
        return value(inventory)
    }

    private func value(_ row: SharedMediaInventoryRecord) -> SharedMediaStorageSnapshot {
        .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }

    private func visit<T: SharedMediaStorageRow>(_ context: ModelContext, _ type: T.Type, body: (T) throws -> Void) throws {
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<T>(sortBy: [SortDescriptor(\.id)])
            descriptor.fetchLimit = SharedMediaStoragePolicy.pageSize
            descriptor.fetchOffset = offset
            let page = try context.fetch(descriptor)
            for row in page { try body(row) }
            if page.count < SharedMediaStoragePolicy.pageSize { break }
            offset += page.count
        }
    }

    private static func binding(authority: String, sources: [String: URL]) throws -> String {
        var parts = [authority]
        for namespace in sources.keys.sorted() {
            try SharedMediaStoragePolicy.token(namespace)
            let root = sources[namespace]!
            parts += [namespace, root.standardizedFileURL.path, try SharedMediaStorageFileOwner.directoryIdentity(root)]
        }
        return SHA256.hash(data: Data(try JSONEncoder().encode(parts))).map { String(format: "%02x", $0) }.joined()
    }

    private func photoLedger(_ context: ModelContext) -> SharedMediaPhotoLedger {
        SharedMediaPhotoLedger(joint: SharedMediaPhotoTransaction(context: context), inventoryID: inventoryID)
    }

    func photoInventory() throws -> SharedMediaPhotoInventory {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        return try photoLedger(state().0).inventory()
    }

    func reservePhoto(_ intent: PhotoPreparationIntent) throws {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        let ledger = photoLedger(context)
        try ledger.reserve(intent)
        try ledger.validate().checkAvailable(files.availableBytes())
        try photoBoundary(.beforeReservationSave)
        _ = try save(context, inventory)
        try photoBoundary(.afterReservationSave)
    }

    func requirePhotoReservation(_ intent: PhotoPreparationIntent) throws {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        try photoBoundary(.beforeReadback)
        try photoLedger(state().0).requireReservation(intent)
    }

    func commitPhoto(_ intent: PhotoPreparationIntent, proof: SharedMediaPhotoFileProof) throws {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        let ledger = photoLedger(context)
        guard proof.binding == storeBinding else { throw SharedMediaStorageFailure.conflict }
        _ = try ledger.commit(intent, file: proof.file, identity: proof.identity)
        _ = try ledger.validate()
        try photoBoundary(.beforeCompletionSave)
        _ = try save(context, inventory)
        try photoBoundary(.afterCompletionSave)
    }

    func completedPhoto(_ intent: PhotoPreparationIntent, file: PhotoPreparationFile) throws -> PhotoOriginalReference {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        try photoBoundary(.beforeReadback)
        return try photoLedger(state().0).completed(intent, file: file)
    }

    func resolvePhoto(_ handle: PhotoOriginalReference) throws -> PhotoPreparationFile {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        return try photoLedger(state().0).resolve(handle)
    }

    func holdPhoto(_ intent: PhotoPreparationIntent) throws {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        let ledger = photoLedger(context)
        try ledger.hold(intent)
        _ = try ledger.validate()
        _ = try save(context, inventory)
    }

    private func photoBoundary(_ boundary: SharedMediaPhotoBoundary) throws {
        #if DEBUG
        try photoFault?(boundary)
        #endif
    }

    private static let photoTypes = Set([ObjectIdentifier(PhotoPreparationRecord.self),
        ObjectIdentifier(PhotoPreparationAsset.self), ObjectIdentifier(PhotoPreparationReference.self),
        ObjectIdentifier(PhotoPreparationLease.self)])

    private static let ledgerTypes = Set([ObjectIdentifier(SharedMediaInventoryRecord.self),
        ObjectIdentifier(SharedMediaAllocationRecord.self), ObjectIdentifier(SharedMediaReferenceRecord.self),
        ObjectIdentifier(SharedMediaLeaseRecord.self)])

    private static func count<T: PersistentModel>(_ context: ModelContext, _ type: T.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    private func one(_ context: ModelContext, id: UUID) throws -> SharedMediaAllocationRecord? {
        var query = FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    private func one(_ context: ModelContext, id: UUID) throws -> SharedMediaReferenceRecord? {
        var query = FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    private func one(_ context: ModelContext, id: UUID) throws -> SharedMediaLeaseRecord? {
        var query = FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

}

private protocol SharedMediaStorageRow: PersistentModel { var id: UUID { get } }
extension SharedMediaAllocationRecord: SharedMediaStorageRow {}
extension SharedMediaReferenceRecord: SharedMediaStorageRow {}
extension SharedMediaLeaseRecord: SharedMediaStorageRow {}

/// Only the shared repository can issue the held-store transaction capability.
struct SharedMediaPhotoTransaction {
    let context: ModelContext
    fileprivate init(context: ModelContext) { self.context = context }
}

struct SharedMediaPhotoBinding {
    let bytes: Data
    let initializing: Bool
    fileprivate init(bytes: Data, initializing: Bool) {
        self.bytes = bytes
        self.initializing = initializing
    }
}

enum SharedMediaPhotoBoundary: Sendable, Equatable { case beforeReservationSave, afterReservationSave, beforeCompletionSave, afterCompletionSave, beforeReadback }
