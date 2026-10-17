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
    let inboxFiles: SharedMediaInboxFiles?
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
        if mode.includesPhotoStorage {
            guard sources.count == (mode == .p1InboxQualification ? 2 : 1), let photoRoot = sources[SharedMediaPhotoLedger.namespace],
                  photoRoot.standardizedFileURL.deletingLastPathComponent() == authorityRoot.standardizedFileURL.deletingLastPathComponent(),
                  configuration.url.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent() == authorityRoot.standardizedFileURL.deletingLastPathComponent(),
                  !photoRoot.standardizedFileURL.pathComponents.starts(with: URL.documentsDirectory.standardizedFileURL.pathComponents) else {
                throw SharedMediaStorageFailure.invalid
            }
        }
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url, sources: sources)
        try files.requireEmpty() // Authority root is separate from store/media; L1 never writes into it.
        rootBinding = try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: configuration.url)
        guard let storeUUID = metadata[NSStoreUUIDKey] as? String, UUID(uuidString: storeUUID) != nil else {
            throw SharedMediaStorageFailure.conflict
        }
        storeIdentity = storeUUID
        storeBinding = try JSONEncoder().encode(["v1", inventoryID.uuidString, storeUUID, rootBinding])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if mode != .observation {
            for type in CurrentSchema.models where !SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(type))
                && !(mode.includesPhotoStorage && SharedMediaStorageLookup.photoTypes.contains(ObjectIdentifier(type)))
                && !(mode == .p1InboxQualification && SharedMediaStorageLookup.inboxTypes.contains(ObjectIdentifier(type))) {
                guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
            }
        }
        let initializing = try !Self.hasLiabilities(in: context)
        if mode == .p1InboxQualification {
            guard let inboxRoot = sources[SharedMediaInboxFiles.namespace],
                  inboxRoot.standardizedFileURL.deletingLastPathComponent() == authorityRoot.standardizedFileURL.deletingLastPathComponent(),
                  !inboxRoot.standardizedFileURL.pathComponents.starts(with: URL.documentsDirectory.standardizedFileURL.pathComponents),
                  !inboxRoot.standardizedFileURL.pathComponents.starts(with: URL.applicationSupportDirectory.standardizedFileURL.pathComponents) else { throw SharedMediaStorageFailure.invalid }
            inboxFiles = try SharedMediaInboxFiles(root: inboxRoot,
                binding: SharedMediaPhotoBinding(bytes: storeBinding, initializing: initializing, epoch: processEpoch))
        } else { inboxFiles = nil }
        if mode.includesPhotoStorage {
            if initializing {
                for type in CurrentSchema.models where SharedMediaStorageLookup.photoTypes.contains(ObjectIdentifier(type)) {
                    guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
                }
            }
            photoFiles = try PhotoPreparationLockedFiles(root: sources[SharedMediaPhotoLedger.namespace]!,
                sharedBinding: SharedMediaPhotoBinding(bytes: storeBinding, initializing: initializing, epoch: processEpoch), inspection: photoInspection)
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
        try SharedMediaStorageLookup.hasLiabilities(in: context)
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
        let observations = try tokens.map { token in
            try files.observe(id: SharedMediaStorageObservation.id(namespace: namespace, token: token), namespace: namespace, token: token)
        }
        try SharedMediaReservationLedger(context: context, inventoryID: inventoryID, mode: mode, sources: Set(sources.keys)).observe(observations)
        inventory.cursor = cursor
        return try save(context, inventory)
    }

    /// Retains a fixed destination reservation only. L1 has no media writer.
    func reserve(_ request: SharedMediaStorageReservation, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        try requireQualification(inventory)
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        guard request.pool != .observed, request.bytes > 0 else { throw SharedMediaStorageFailure.invalid }
        if let prior: SharedMediaAllocationRecord = try SharedMediaStorageLookup.one(context, id: request.id) {
            guard prior.stateRaw == "reserved", prior.accountID == request.accountID,
                  prior.packageID == request.packageID, prior.poolRaw == request.pool.rawValue,
                  prior.reservedBytes == request.bytes else { throw SharedMediaStorageFailure.conflict }
            return value(inventory) // Exact saved reservation, never a renewed identity/allowance.
        }
        try revision(inventory, expected)
        try SharedMediaStorageLookup.visit(context, SharedMediaAllocationRecord.self) {
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
        if let prior: SharedMediaReferenceRecord = try SharedMediaStorageLookup.one(context, id: id) {
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
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard let edge: SharedMediaReferenceRecord = try SharedMediaStorageLookup.one(context, id: id) else { throw SharedMediaStorageFailure.invalid }
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
        if let old: SharedMediaLeaseRecord = try SharedMediaStorageLookup.one(context, id: id) {
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
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard let lease: SharedMediaLeaseRecord = try SharedMediaStorageLookup.one(context, id: id),
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
        guard let allocation: SharedMediaAllocationRecord = try SharedMediaStorageLookup.one(context, id: allocationID),
              allocation.poolRaw != "observed" else { throw SharedMediaStorageFailure.invalid }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if allocation.stateRaw == "retiring" { return value(inventory) }
        try revision(inventory, expected)
        _ = try mutableAllocation(context, allocationID)
        var held = false
        try SharedMediaStorageLookup.visit(context, SharedMediaReferenceRecord.self) { if $0.allocationID == allocationID && $0.stateRaw != "retired" { held = true } }
        try SharedMediaStorageLookup.visit(context, SharedMediaLeaseRecord.self) { if $0.allocationID == allocationID && $0.stateRaw != "closed" { held = true } }
        guard !held else { throw SharedMediaStorageFailure.inUse }
        allocation.stateRaw = "retiring" // Irreversible; bytes remain charged, no physical-release API.
        return try save(context, inventory)
    }

    /// Global admission closure only; preserves every reference, lease and charge.
    func closeAdmission(expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if inventory.phaseRaw == "retiring" { return value(inventory) }
        try revision(inventory, expected)
        inventory.phaseRaw = "retiring"
        return try save(context, inventory)
    }

    /// Local account reference retirement only, not permission to erase files or remote data.
    func retireAccountReferences(_ accountID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        try revision(inventory, expected)
        try SharedMediaStorageLookup.visit(context, SharedMediaReferenceRecord.self) {
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
              rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)), item.storeIdentity == storeIdentity,
              item.modeRaw == mode.rawValue, item.revision >= 0,
              (mode.includesPhotoStorage ? item.phaseRaw == "readyP1" :
                (mode == .qualification ? ["readyQualification", "retiring"].contains(item.phaseRaw) : ["observing", "retiring"].contains(item.phaseRaw))) else {
            throw SharedMediaStorageFailure.conflict
        }
        if mode.includesPhotoStorage {
            try inboxFiles?.check()
            try photoFiles?.checkIdentity()
            for type in CurrentSchema.models where !SharedMediaStorageLookup.ledgerTypes.contains(ObjectIdentifier(type)) && !SharedMediaStorageLookup.photoTypes.contains(ObjectIdentifier(type))
                && !(mode == .p1InboxQualification && SharedMediaStorageLookup.inboxTypes.contains(ObjectIdentifier(type))) {
                guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.conflict }
            }
        }
        _ = try accounting(context)
        return (context, item)
    }

    private func accounting(_ context: ModelContext) throws -> SharedMediaStoragePolicy.Totals {
        if mode == .p1InboxQualification {
            guard let inventory = try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first else { throw SharedMediaStorageFailure.conflict }
            return try inboxLedger(context, inventory).validate()
        }
        if mode == .p1Qualification { return try photoLedger(context).validate() }
        return try SharedMediaReservationLedger(context: context, inventoryID: inventoryID, mode: mode, sources: Set(sources.keys)).validate()
    }

    private func mutableAllocation(_ context: ModelContext, _ id: UUID) throws -> SharedMediaAllocationRecord {
        guard let item: SharedMediaAllocationRecord = try SharedMediaStorageLookup.one(context, id: id), item.stateRaw == "reserved" else {
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
        guard rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else { throw SharedMediaStorageFailure.conflict }
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        try context.save()
        return value(inventory)
    }

    private func value(_ row: SharedMediaInventoryRecord) -> SharedMediaStorageSnapshot {
        .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
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

    func preparePhotoShare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) throws -> SharedMediaPhotoShareRequest {
        _ = try resolvePhoto(source)
        return try .init(source: source, packageID: packageID, draftGeneration: draftGeneration, snapshot: snapshot())
    }

    func sharedPhoto(_ request: SharedMediaPhotoShareRequest) throws -> PhotoOriginalReference? {
        try photoBoundary(.beforeLifecycleReadback)
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard request.inventoryGeneration == inventory.generation else { throw SharedMediaStorageFailure.stale }
        let handle = try request.destination()
        guard let (_, _, retiring) = try photoLedger(context).reference(handle) else { return nil }
        guard !retiring else { throw SharedMediaStorageFailure.stale }
        _ = try photoLedger(context).resolve(handle)
        return handle
    }

    func sharePhoto(_ request: SharedMediaPhotoShareRequest) throws {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state()
        guard request.inventoryGeneration == inventory.generation, request.expectedRevision == inventory.revision else { throw SharedMediaStorageFailure.stale }
        let ledger = photoLedger(context)
        try ledger.share(request)
        try ledger.validate().checkAvailable(files.availableBytes())
        try photoBoundary(.beforeShareSave)
        _ = try save(context, inventory)
        try photoBoundary(.afterShareSave)
    }

    func photoReferenceState(_ handle: PhotoOriginalReference) throws -> SharedMediaPhotoReferenceState {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        try photoBoundary(.beforeLifecycleReadback)
        let ledger = try photoLedger(state().0)
        guard let (file, identity, retiring) = try ledger.reference(handle) else { return .absent }
        if !retiring { return .live(file) }
        return try .retiring(.init(handle: handle, file: file, identity: .decode(identity), binding: storeBinding, epoch: processEpoch))
    }

    func retirePhoto(_ handle: PhotoOriginalReference, inspection: SharedMediaPhotoRetirementInspection) throws {
        guard mode == .p1Qualification, inspection.binding == storeBinding, inspection.epoch == processEpoch else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state(), ledger = photoLedger(context)
        try ledger.retire(handle, inspection: inspection)
        _ = try ledger.validate()
        try photoBoundary(.beforeRetirementSave)
        _ = try save(context, inventory)
        try photoBoundary(.afterRetirementSave)
    }

    func photoRetirements(ownerID: UUID) throws -> [SharedMediaPhotoRetirement] {
        guard mode == .p1Qualification else { throw SharedMediaStorageFailure.closed }
        return try photoLedger(state().0).retirementHandles(ownerID: ownerID).map {
            guard case .retiring(let intent) = try photoReferenceState($0) else { throw SharedMediaStorageFailure.conflict }
            return intent
        }
    }

    func releasePhoto(_ proof: SharedMediaPhotoReleaseProof) throws {
        let intent = proof.retirement
        guard mode == .p1Qualification, intent.binding == storeBinding, intent.epoch == processEpoch else { throw SharedMediaStorageFailure.closed }
        let (context, inventory) = try state(), ledger = photoLedger(context)
        try ledger.release(intent)
        _ = try ledger.validate()
        try photoBoundary(.beforeReleaseSave)
        _ = try save(context, inventory)
        try photoBoundary(.afterReleaseSave)
    }

    private func photoBoundary(_ boundary: SharedMediaPhotoBoundary) throws {
        #if DEBUG
        try photoFault?(boundary)
        #endif
    }

    private func inboxLedger(_ context: ModelContext, _ inventory: SharedMediaInventoryRecord) throws -> SharedMediaInboxLedger {
        guard mode == .p1InboxQualification, let inboxFiles else { throw SharedMediaStorageFailure.closed }
        return SharedMediaInboxLedger(joint: SharedMediaPhotoTransaction(context: context), inventory: inventory,
            binding: SharedMediaPhotoBinding(bytes: storeBinding, initializing: false, epoch: processEpoch), rootIdentity: inboxFiles.identity)
    }

    func inboxSources() throws -> [SharedMediaInboxSource] {
        let (context, inventory) = try state()
        return try inboxLedger(context, inventory).sources()
    }

    func inboxSource(_ handle: SharedMediaInboxHandle) throws -> SharedMediaInboxSource {
        let (context, inventory) = try state()
        return try inboxLedger(context, inventory).source(handle)
    }

    func inboxRetirement(_ handle: SharedMediaInboxHandle) throws -> SharedMediaInboxRetirement {
        let source = try inboxSource(handle)
        guard source.phase == "retiring", source.writerState == "closed", source.retirementID != nil else { throw SharedMediaStorageFailure.conflict }
        return .init(source: source, binding: storeBinding, epoch: processEpoch)
    }

    func inboxWrite<T>(before: SharedMediaInboxBoundary, after: SharedMediaInboxBoundary, requiresFreeSpace: Bool = false,
                       _ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        let (context, inventory) = try state(), ledger = try inboxLedger(context, inventory)
        let result = try body(ledger)
        let totals = try ledger.validate()
        if requiresFreeSpace { try totals.checkAvailable(files.availableBytes()) }
        #if DEBUG
        try inboxFault?(before)
        #endif
        _ = try save(context, inventory)
        #if DEBUG
        try inboxFault?(after)
        #endif
        return result
    }

    func inboxRead<T>(_ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        let (context, inventory) = try state()
        return try body(inboxLedger(context, inventory))
    }

    func handoffWrite<T>(before: SharedMediaInboxHandoffBoundary, after: SharedMediaInboxHandoffBoundary,
                         requiresFreeSpace: Bool = false, additionalFreeBytes: Int64 = 0, _ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        let (context, inventory) = try state(), ledger = try inboxLedger(context, inventory)
        let result = try body(ledger), totals = try ledger.validate()
        if requiresFreeSpace {
            #if DEBUG
            try totals.checkAvailable(handoffAvailableBytes ?? files.availableBytes(), additionalReservation: additionalFreeBytes)
            #else
            try totals.checkAvailable(files.availableBytes(), additionalReservation: additionalFreeBytes)
            #endif
        }
        #if DEBUG
        try handoffFault?(before)
        #endif
        _ = try save(context, inventory)
        #if DEBUG
        try handoffFault?(after)
        #endif
        return result
    }

    func detachedRetirement(_ request: SharedMediaInboxHandoffRequest) throws -> SharedMediaInboxDestinationRetirement {
        let (state, identity) = try inboxRead { try $0.handoffs.detachedRetirement(request) }
        return .init(handoff: state, identity: identity, binding: storeBinding, epoch: processEpoch)
    }

    func derivativeRetirements(_ request: SharedMediaDerivativeRequest) throws -> [SharedMediaDerivativeRetirement] {
        let values = try inboxRead { ledger in
            guard let pair = try ledger.derivatives.saved(request), pair.phase == "retiring" else { throw SharedMediaStorageFailure.stale }
            return try pair.work.map { ($0, try ledger.derivatives.retirementIdentity($0)) }
        }
        return values.map { .init(work: $0.0, identity: $0.1, binding: storeBinding, epoch: processEpoch) }
    }

    var inboxEpoch: UUID { processEpoch }
    #if DEBUG
    var inboxFault: ((SharedMediaInboxBoundary) throws -> Void)?
    var handoffAvailableBytes: Int64?
    var handoffFault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?
    #endif


}

/// Only the shared repository can issue the held-store transaction capability.
struct SharedMediaPhotoTransaction {
    let context: ModelContext
    fileprivate init(context: ModelContext) { self.context = context }
}

struct SharedMediaPhotoBinding {
    let bytes: Data
    let initializing: Bool
    let epoch: UUID
    fileprivate init(bytes: Data, initializing: Bool, epoch: UUID) {
        self.bytes = bytes
        self.initializing = initializing
        self.epoch = epoch
    }
}

/// Only this repository can authorize the namespace owner to release an intent.
struct SharedMediaPhotoRetirement: Equatable, Sendable {
    let handle: PhotoOriginalReference
    let file: PhotoPreparationFile
    let identity: SharedMediaPhotoRetirementIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(handle: PhotoOriginalReference, file: PhotoPreparationFile,
                     identity: SharedMediaPhotoRetirementIdentity, binding: Data, epoch: UUID) {
        self.handle = handle; self.file = file; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}

/// Only a fresh read of saved intent through the fenced repository can mint
/// physical source-release authority. An unsaved ledger mutation cannot.
struct SharedMediaInboxRetirement: Sendable {
    let source: SharedMediaInboxSource
    let binding: Data
    let epoch: UUID
    fileprivate init(source: SharedMediaInboxSource, binding: Data, epoch: UUID) {
        self.source = source; self.binding = binding; self.epoch = epoch
    }
}

/// Fresh saved-intent readback is required before this namespace capability.
struct SharedMediaInboxDestinationRetirement: Sendable {
    let handoff: SharedMediaInboxHandoff
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}

/// Minted only by a fresh saved-intent read under the repository's store fence.
struct SharedMediaDerivativeRetirement: Sendable {
    let work: SharedMediaDerivativeWork
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(work: SharedMediaDerivativeWork, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.work = work; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
