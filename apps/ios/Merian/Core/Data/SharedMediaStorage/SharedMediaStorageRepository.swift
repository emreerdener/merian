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
    private let purgeCoordinatorID: UUID?
    private lazy var purgeAuthority = makePurgeAuthority()
    let inboxFiles: SharedMediaInboxFiles?
    let photoFiles: PhotoPreparationLockedFiles?
    #if DEBUG
    var photoFault: ((SharedMediaPhotoBoundary) throws -> Void)?
    #endif

    init(container: ModelContainer, authorityRoot: URL, inventoryID: UUID, mode: SharedMediaStorageMode, sources: [String: URL] = [:],
         photoInspection: PhotoPreparationDirectoryInspection = .init(), purgeCoordinatorID: UUID? = nil, resumePurgeID: UUID? = nil) throws {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly else { throw SharedMediaStorageFailure.invalid }
        self.purgeCoordinatorID = purgeCoordinatorID
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
        // V63 schema foundation does not grant consumer-aware qualification or cleanup.
        guard try context.fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 0 else {
            throw SharedMediaStorageFailure.closed
        }
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
        let initial = try state(allowPurge: resumePurgeID != nil).1
        if let resumePurgeID {
            guard try SharedMediaPurgeState.read(initial).id == resumePurgeID else { throw SharedMediaStorageFailure.stale }
        }
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

    func reserve(_ request: SharedMediaStorageReservation, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.reserve(request, expected: expected, availableBytes: { try files.availableBytes() }) else { return value(inventory) }
        return try save(context, inventory)
    }

    func acquireReference(id: UUID, allocationID: UUID, accountID: UUID, ownerID: String,
                          role: String, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.acquireReference(id: id, allocationID: allocationID, accountID: accountID, ownerID: ownerID, role: role, expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    func releaseReference(id: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.releaseReference(id: id, expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    func startLocalLease(id: UUID, allocationID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.startLocalLease(id: id, allocationID: allocationID, expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    func finishLocalLease(id: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.finishLocalLease(id: id, expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    func retire(allocationID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.retire(allocationID: allocationID, expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    func closeAdmission(expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.closeAdmission(expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    func retireAccountReferences(_ accountID: UUID, expected: SharedMediaStorageSnapshot) throws -> SharedMediaStorageSnapshot {
        let (context, inventory) = try state()
        let ledger = SharedMediaQualificationLedger(context: context, inventory: inventory, mode: mode, processEpoch: processEpoch)
        guard try ledger.retireAccountReferences(accountID, expected: expected) else { return value(inventory) }
        return try save(context, inventory)
    }

    private func state(allowPurge: Bool = false) throws -> (ModelContext, SharedMediaInventoryRecord) {
        try files.requireEmpty()
        try files.bindStore(storeBinding, initializing: false)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        // V63 schema foundation does not grant consumer-aware qualification or cleanup.
        guard try context.fetchCount(FetchDescriptor<SharedMediaConsumerRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>()) == 0 else {
            throw SharedMediaStorageFailure.closed
        }
        var query = FetchDescriptor<SharedMediaInventoryRecord>()
        query.fetchLimit = 2
        let inventories = try context.fetch(query)
        guard inventories.count == 1, let item = inventories.first,
              item.id == inventoryID, item.rootIdentity == rootBinding,
              rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)), item.storeIdentity == storeIdentity,
              item.modeRaw == mode.rawValue, item.revision >= 0,
              (mode.includesPhotoStorage ? (item.phaseRaw == "readyP1" || (allowPurge && mode == .p1InboxQualification && ["purgingP1", "purgedP1"].contains(item.phaseRaw))) :
                (mode == .qualification ? ["readyQualification", "retiring"].contains(item.phaseRaw) : ["observing", "retiring"].contains(item.phaseRaw))) else {
            throw SharedMediaStorageFailure.conflict
        }
        if mode == .p1InboxQualification && item.phaseRaw != "readyP1" { _ = try SharedMediaPurgeState.read(item) }
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

    func inboxRetirement(_ handle: SharedMediaInboxHandle, purge: SharedMediaPurgeAccess? = nil) throws -> SharedMediaInboxRetirement {
        let source = try purge.map { try purgeRead($0) { try $0.source(handle) } } ?? inboxSource(handle)
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

    func detachedRetirement(_ request: SharedMediaInboxHandoffRequest, purge: SharedMediaPurgeAccess? = nil) throws -> SharedMediaInboxDestinationRetirement {
        let read: (SharedMediaInboxLedger) throws -> (SharedMediaInboxHandoff, SharedMediaInboxDestinationRetirementIdentity) = { try $0.handoffs.detachedRetirement(request) }
        let (state, identity) = try purge.map { try purgeRead($0, read) } ?? inboxRead(read)
        return .init(handoff: state, identity: identity, binding: storeBinding, epoch: processEpoch)
    }

    func derivativeRetirements(_ request: SharedMediaDerivativeRequest, purge: SharedMediaPurgeAccess? = nil) throws -> [SharedMediaDerivativeRetirement] {
        let read: (SharedMediaInboxLedger) throws -> [(SharedMediaDerivativeWork, SharedMediaInboxDestinationRetirementIdentity)] = { ledger in
            guard let pair = try ledger.derivatives.saved(request), pair.phase == "retiring" else { throw SharedMediaStorageFailure.stale }
            return try pair.work.map { ($0, try ledger.derivatives.retirementIdentity($0)) }
        }
        let values = try purge.map { try purgeRead($0, read) } ?? inboxRead(read)
        return values.map { .init(work: $0.0, identity: $0.1, binding: storeBinding, epoch: processEpoch) }
    }

    private func makePurgeAuthority() -> SharedMediaPurgeAuthority {
        .init(transaction: .init(container: container, binding: storeBinding, epoch: processEpoch, coordinatorID: purgeCoordinatorID,
            read: { [weak self] in
                guard let self, self.mode == .p1InboxQualification else { throw SharedMediaStorageFailure.closed }
                return try self.state(allowPurge: true)
            }, save: { [weak self] context, inventory in
                guard let self else { throw SharedMediaStorageFailure.closed }; _ = try self.save(context, inventory)
            }, ledger: { [weak self] context, inventory in
                guard let self else { throw SharedMediaStorageFailure.closed }; return try self.inboxLedger(context, inventory)
            }, verifyEmpty: { [weak self] in
                guard let self, let inboxFiles = self.inboxFiles, let photoFiles = self.photoFiles else { throw SharedMediaStorageFailure.closed }
                try inboxFiles.validateInventory([]); try photoFiles.requireSharedEmptyNamespace()
            }))
    }
    func purgePhotoState(_ handle: PhotoOriginalReference, access: SharedMediaPurgeAccess) throws -> SharedMediaPhotoReferenceState {
        guard let (file, identity, retiring) = try purgeRead(access, { try $0.photos.reference(handle) }) else { return .absent }
        if !retiring { return .live(file) }
        return try .retiring(.init(handle: handle, file: file, identity: .decode(identity), binding: storeBinding, epoch: processEpoch))
    }

    func purgeRetirePhoto(_ handle: PhotoOriginalReference, inspection: SharedMediaPhotoRetirementInspection,
                          access: SharedMediaPurgeAccess) throws {
        guard inspection.binding == storeBinding, inspection.epoch == processEpoch else { throw SharedMediaStorageFailure.closed }
        try purgeWrite(access, before: .beforeRetirementSave, after: .afterRetirementSave) { try $0.photos.retire(handle, inspection: inspection) }
    }

    func purgeReleasePhoto(_ proof: SharedMediaPhotoReleaseProof, access: SharedMediaPurgeAccess) throws {
        guard proof.retirement.binding == storeBinding, proof.retirement.epoch == processEpoch else { throw SharedMediaStorageFailure.closed }
        try purgeWrite(access, before: .beforeReleaseSave, after: .afterReleaseSave) { try $0.photos.release(proof.retirement) }
    }

    func requirePurgeContainer(_ target: ModelContainer) throws {
        guard target === container, mode == .p1InboxQualification else { throw SharedMediaStorageFailure.conflict }
        _ = try state(allowPurge: true)
    }
    func beginPurge(id: UUID) throws { try purgeAuthority.begin(id: id) }
    func purgeAccess(id: UUID, drained: SharedMediaPurgeDrain) throws -> SharedMediaPurgeAccess { try purgeAuthority.access(id: id, drained: drained) }
    func purgeRead<T>(_ access: SharedMediaPurgeAccess, _ body: (SharedMediaInboxLedger) throws -> T) throws -> T { try purgeAuthority.read(access, body) }
    func purgeWrite<T>(_ access: SharedMediaPurgeAccess, before: SharedMediaPurgeBoundary, after: SharedMediaPurgeBoundary,
                       _ body: (SharedMediaInboxLedger) throws -> T) throws -> T { try purgeAuthority.write(access, before: before, after: after, body) }
    func isPurgeComplete(_ access: SharedMediaPurgeAccess) throws -> Bool { try purgeAuthority.isComplete(access) }
    func finishPurge(_ access: SharedMediaPurgeAccess) throws -> SharedMediaPurgeCompletion { try purgeAuthority.finish(access) }
    #if DEBUG
    func setPurgeFault(_ fault: ((SharedMediaPurgeBoundary) throws -> Void)?) { purgeAuthority.fault = fault }
    #endif

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

/// Only this fenced repository supplies identity-checked lifecycle transactions.
@MainActor
struct SharedMediaPurgeTransaction {
    let container: ModelContainer
    let binding: Data
    let epoch: UUID
    let coordinatorID: UUID?
    let read: () throws -> (ModelContext, SharedMediaInventoryRecord)
    let save: (ModelContext, SharedMediaInventoryRecord) throws -> Void
    let ledger: (ModelContext, SharedMediaInventoryRecord) throws -> SharedMediaInboxLedger
    let verifyEmpty: () throws -> Void
    fileprivate init(container: ModelContainer, binding: Data, epoch: UUID, coordinatorID: UUID?,
                     read: @escaping () throws -> (ModelContext, SharedMediaInventoryRecord),
                     save: @escaping (ModelContext, SharedMediaInventoryRecord) throws -> Void,
                     ledger: @escaping (ModelContext, SharedMediaInventoryRecord) throws -> SharedMediaInboxLedger,
                     verifyEmpty: @escaping () throws -> Void) {
        self.container = container; self.binding = binding; self.epoch = epoch; self.coordinatorID = coordinatorID
        self.read = read; self.save = save; self.ledger = ledger; self.verifyEmpty = verifyEmpty
    }
}
