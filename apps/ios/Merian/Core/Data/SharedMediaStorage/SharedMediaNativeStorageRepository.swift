import CoreData
import Foundation
import SwiftData

/// Native-private fixture-store admission. No media mutation, purge or
/// production composition is exposed until the closed native owners qualify.
@MainActor
final class SharedMediaNativeStorageRepository {
    private static let mode = "nativeQualificationV1"
    private static let phase = "readyNativeAccountingV1"
    private let container: ModelContainer
    private let files: SharedMediaStorageFileOwner
    private let photos: PhotoPreparationLockedFiles
    private let originals: Bool
    private let expectedOwnerID: UUID?
    private let originalWriterEpoch: UUID?
    private let originalIO: SharedMediaNativeOriginalIO
    private let inbox: SharedMediaInboxFiles
    private let inventoryID: UUID
    private let generation: UUID
    private let storeIdentity: String
    private let rootBinding: String
    private let binding: Data
    private let nativeBinding: SharedMediaNativeBinding
    #if DEBUG
    fileprivate var acquisitionFault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?
    #endif
    private let sources: [String: URL]

    #if DEBUG
    static func qualification(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                              inboxRoot: URL, inventoryID: UUID) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: nil)
    }

    static func qualification(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                              inboxRoot: URL, inventoryID: UUID,
                              fault: @escaping (SharedMediaNativeInitializationBoundary) throws -> Void) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: fault)
    }
    #endif

    private init(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
                 inventoryID: UUID, fault: ((SharedMediaNativeInitializationBoundary) throws -> Void)?,
                 originals: Bool = false, expectedOwnerID: UUID? = nil, originalWriterEpoch: UUID? = nil, pause: (@Sendable () async -> Void)? = nil) throws {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.invalid }
        let parent = authorityRoot.standardizedFileURL.deletingLastPathComponent()
        guard photoRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              inboxRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              configuration.url.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent() == parent,
              [authorityRoot, photoRoot, inboxRoot, configuration.url, configuration.url.deletingLastPathComponent()].allSatisfy(Self.fixtureLocation) else {
            throw SharedMediaStorageFailure.invalid
        }
        self.originalWriterEpoch = originalWriterEpoch
        self.container = container; self.inventoryID = inventoryID; self.originals = originals; self.expectedOwnerID = expectedOwnerID
        sources = [SharedMediaPhotoLedger.namespace: photoRoot, SharedMediaInboxFiles.namespace: inboxRoot]
        // The supplied container already exists. Fence before eligibility reads,
        // metadata/bindings and every subsequent operation, not before its creation.
        files = try SharedMediaStorageFileOwner(root: authorityRoot, storeURL: configuration.url, sources: sources)
        try files.requireEmpty()
        rootBinding = try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: configuration.url)
        guard let storeUUID = metadata[NSStoreUUIDKey] as? String, UUID(uuidString: storeUUID) != nil else {
            throw SharedMediaStorageFailure.conflict
        }
        storeIdentity = storeUUID
        binding = try JSONEncoder().encode([Self.mode, inventoryID.uuidString, storeUUID, rootBinding])
        let context = ModelContext(container); context.autosaveEnabled = false
        let existing = try originals
            ? Self.originalState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding)
            : Self.emptyState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding)
        if originals {
            guard let expectedOwnerID else { throw SharedMediaStorageFailure.invalid }
            try Self.requireOriginalAccount(context, ownerID: expectedOwnerID)
        }
        let initializing = existing == nil
        generation = existing?.generation ?? UUID()
        if initializing {
            // Unknown fixture-root content is never adopted, cleared or converted.
            for root in [photoRoot, inboxRoot] {
                guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else { throw SharedMediaStorageFailure.conflict }
            }
        }
        let native = SharedMediaNativeBinding(bytes: binding, initializing: initializing, epoch: UUID())
        nativeBinding = SharedMediaNativeBinding(bytes: binding, initializing: false, epoch: native.epoch)
        photos = try PhotoPreparationLockedFiles(root: photoRoot, sharedBinding: .init(native: native))
        originalIO = SharedMediaNativeOriginalIO(files: photos, binding: native, pause: pause)
        try fault?(.afterPhotoBinding)
        inbox = try SharedMediaInboxFiles(root: inboxRoot, binding: .init(native: native))
        try fault?(.afterInboxBinding)
        try files.bindStore(binding, initializing: initializing)
        try fault?(.afterAuthorityBinding)
        if initializing {
            context.insert(SharedMediaInventoryRecord(id: inventoryID, rootIdentity: rootBinding,
                storeIdentity: storeIdentity, generation: generation, revision: 0,
                modeRaw: Self.mode, phaseRaw: Self.phase, cursor: ""))
            context.insert(SharedMediaMembershipBootstrapRecord(inventoryID: inventoryID, inventoryGeneration: generation))
            try fault?(.beforeSave)
            try context.save()
            try fault?(.afterSave)
        }
        if !originals { _ = try snapshot() }
    }

    /// Exact fresh read only. Nonempty native graphs remain unsupported here;
    /// an audit snapshot is not a constructor, writer or cleanup capability.
    func snapshot() throws -> SharedMediaStorageSnapshot {
        guard !originals else { throw SharedMediaStorageFailure.closed }
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try files.requireEmpty()
        try files.bindStore(binding, initializing: false)
        guard rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else {
            throw SharedMediaStorageFailure.conflict
        }
        try photos.requireSharedEmptyNamespace()
        guard let photoRoot = sources[SharedMediaPhotoLedger.namespace],
              try FileManager.default.contentsOfDirectory(atPath: photoRoot.path) == ["PhotoPreparation"] else {
            throw SharedMediaStorageFailure.conflict
        }
        try inbox.validateInventory([])
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let row = try Self.emptyState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding),
              row.generation == generation else { throw SharedMediaStorageFailure.conflict }
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }

    /// Only the same-file registered controller can begin nonempty admission.
    fileprivate static func originalAdmission(container: ModelContainer, authorityRoot: URL, photoRoot: URL,
                                              inboxRoot: URL, inventoryID: UUID, ownerID: UUID, writerEpoch: UUID,
                                              pause: (@Sendable () async -> Void)?) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: nil, originals: true, expectedOwnerID: ownerID, originalWriterEpoch: writerEpoch, pause: pause)
    }

    fileprivate func inspectOriginals(check: @escaping @MainActor () throws -> Void) async throws -> SharedMediaNativeOriginalSnapshot {
        try check()
        let expected = try originalHeader(audit: true)
        try check(); try requireOriginalHeader(expected)
        var offset = 0, recovery = false
        while true {
            let page = try originalPage(offset: offset)
            for entry in page {
                switch entry.receipt {
                case .completed(let request, let result):
                    try await originalIO.verify(request: request, result: result, retirement: entry.retirement)
                    try check(); try requireOriginalHeader(expected)
                    recovery = recovery || entry.retirement != nil
                case .reserved, .held: recovery = true
                case .released: break
                }
            }
            if page.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(page.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        // Reverse hashes/absence checks may suspend. Finish with the complete
        // leaf stream so additions and replacements during those awaits cannot
        // escape the forward join. Cooperating writers remain fenced throughout.
        try await originalIO.visit { @MainActor [self] leaf in
            try check(); try requireOriginalHeader(expected)
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventory = try originalInventory(context)
            let base = leaf.token.hasSuffix(".partial") ? String(leaf.token.dropLast(8)) : leaf.token
            guard let last = base.split(separator: "/").last, let id = UUID(uuidString: String(last)) else {
                throw SharedMediaStorageFailure.conflict
            }
            let row = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == id }))
            switch try SharedMediaNativeAcquisitionGraph.receipt(row, inventory: inventory, context: context) {
            case .reserved(let request), .held(let request):
                guard [request.finalToken, request.partialToken].contains(leaf.token), leaf.byteCount <= request.maximumBytes else {
                    throw SharedMediaStorageFailure.conflict
                }
            case .completed(let request, let result):
                guard leaf.token == request.finalToken, leaf.byteCount == result.byteCount, leaf.descriptor == result.descriptor.file else {
                    throw SharedMediaStorageFailure.conflict
                }
            case .released: throw SharedMediaStorageFailure.conflict
            }
        }
        try check()
        guard try originalHeader(audit: true) == expected else { throw SharedMediaStorageFailure.conflict }
        return .init(inventory: expected, requiresRecovery: recovery)
    }

    fileprivate func originalRequest(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                                     kind: SharedMediaAcquisitionIntent.Kind, epoch: UUID) throws -> SharedMediaAcquisitionIntent {
        let snapshot = try originalHeader(audit: true)
        guard let ownerID = expectedOwnerID else { throw SharedMediaStorageFailure.closed }
        let context = ModelContext(container); context.autosaveEnabled = false
        var query = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        if let row = rows.first {
            guard row.ownerID == ownerID, row.draftGeneration == draftGeneration, row.accountingTierRaw == "pending",
                  row.phaseRaw == "draftOwned", !row.retirementRequested else { throw SharedMediaStorageFailure.stale }
        }
        let request = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: inventoryID, inventoryGeneration: snapshot.generation,
            ownerID: ownerID, expectedInventoryRevision: snapshot.revision, packageID: packageID, draftGeneration: draftGeneration,
            packageExpectation: rows.first.map { .revision($0.revision) } ?? .absent, assetID: UUID(), assetGeneration: UUID(),
            referenceID: UUID(), ordinal: ordinal, kind: kind, writerEpoch: epoch, maximumBytes: PhotoPreparationPolicy.original)
        try request.validate(); return request
    }

    fileprivate func originalReceipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
        try acquisitionBoundary(.beforeReadback)
        _ = try originalHeader(audit: true)
        guard request.inventoryID == inventoryID, request.inventoryGeneration == generation,
              request.ownerID == expectedOwnerID else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = request.operationID
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return try rows.first.map { try SharedMediaAcquisitionReceipt.read($0, expected: request) }
    }

    fileprivate func reservedState(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativeReservedState {
        guard case .reserved = try originalReceipt(request) else { throw SharedMediaStorageFailure.conflict }
        return try .init(inventory: originalHeader(audit: true), context: ModelContext(container), request: request)
    }

    fileprivate func reserveOriginal(_ request: SharedMediaAcquisitionIntent, check: @escaping @MainActor () throws -> Void) throws {
        _ = try originalHeader(audit: true)
        let transaction = try SharedMediaNativeAcquisitionMutation.reserve(container: container, request: request,
            authority: mutationAuthority(check: check), availableBytes: files.availableBytes())
        try acquisitionBoundary(.beforeReservationSave); try transaction.save(); try acquisitionBoundary(.afterReservationSave)
    }

    fileprivate func writeOriginal(_ data: Data, request: SharedMediaAcquisitionIntent) async throws -> SharedMediaPhotoRetirementInspection {
        let proof = try await originalIO.write(data, request: request)
        try acquisitionBoundary(.afterOriginalWrite)
        return proof
    }
    fileprivate func loadOriginal(_ provider: @Sendable () async throws -> Data) async throws -> Data { try await originalIO.load(provider) }

    fileprivate func completeOriginal(_ request: SharedMediaAcquisitionIntent, proof: SharedMediaPhotoRetirementInspection,
                                      check: @escaping @MainActor () throws -> Void) throws {
        let transaction = try SharedMediaNativeAcquisitionMutation.complete(container: container, request: request,
            authority: mutationAuthority(check: check), proof: proof)
        try acquisitionBoundary(.beforeCompletionSave); try transaction.save(); try acquisitionBoundary(.afterCompletionSave)
    }

    fileprivate func holdOriginal(_ request: SharedMediaAcquisitionIntent) throws {
        let transaction = try SharedMediaNativeAcquisitionMutation.hold(container: container, request: request,
            authority: mutationAuthority(check: {}))
        try acquisitionBoundary(.beforeHeldSave); try transaction.save(); try acquisitionBoundary(.afterHeldSave)
    }
    private func mutationAuthority(check: @escaping @MainActor () throws -> Void) throws -> SharedMediaNativeMutationAuthority {
        guard let expectedOwnerID, let originalWriterEpoch else { throw SharedMediaStorageFailure.closed }
        return .init(binding: nativeBinding, ownerID: expectedOwnerID, writerEpoch: originalWriterEpoch) { [self] in
            try check()
            _ = try originalHeader(audit: true)
        }
    }
    private func acquisitionBoundary(_ boundary: SharedMediaNativeAcquisitionBoundary) throws {
        #if DEBUG
        try acquisitionFault?(boundary)
        #endif
    }

    private struct OriginalEntry: Sendable {
        let receipt: SharedMediaAcquisitionReceipt
        let retirement: SharedMediaNativeRetirementIdentity?
    }

    private func originalPage(offset: Int) throws -> [OriginalEntry] {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try originalInventory(context)
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize; query.fetchOffset = offset
        return try context.fetch(query).map { row in
            let receipt = try SharedMediaNativeAcquisitionGraph.receipt(row, inventory: inventory, context: context)
            let retirement: SharedMediaNativeRetirementIdentity?
            if case .completed(let request, _) = receipt {
                retirement = try SharedMediaNativeOriginalAccounting.audit(assetID: request.assetID, inventoryID: inventoryID, context: context).retirement
            } else { retirement = nil }
            return .init(receipt: receipt, retirement: retirement)
        }
    }

    private func requireOriginalHeader(_ expected: SharedMediaStorageSnapshot) throws {
        guard try originalHeader(audit: false) == expected else { throw SharedMediaStorageFailure.conflict }
    }

    private func originalHeader(audit: Bool) throws -> SharedMediaStorageSnapshot {
        guard originals, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try files.requireEmpty(); try files.bindStore(binding, initializing: false); try photos.checkIdentity()
        guard rootBinding == (try SharedMediaStorageLookup.binding(authority: files.identity, sources: sources)) else { throw SharedMediaStorageFailure.conflict }
        try inbox.validateInventory([])
        let context = ModelContext(container); context.autosaveEnabled = false
        let row = try originalInventory(context)
        if audit {
            guard let expectedOwnerID else { throw SharedMediaStorageFailure.closed }
            try Self.requireOriginalAccount(context, ownerID: expectedOwnerID)
            try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
            _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: row)
        }
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }

    private func originalInventory(_ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = inventoryID
        let row = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        guard row.generation == generation, row.storeIdentity == storeIdentity, row.rootIdentity == rootBinding,
              row.modeRaw == Self.mode, row.phaseRaw == Self.phase, row.cursor.isEmpty, row.revision >= 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        return row
    }

    private func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        var query = query; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }

    private static func requireOriginalAccount(_ context: ModelContext, ownerID: UUID) throws {
        // Full and stripped terminal receipts both retain their account identity.
        // Package ownership also covers empty drafts without an acquisition row.
        guard try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.ownerID != ownerID })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.ownerID != ownerID })) == 0 else {
            throw PhotoPreparationFailure.accountChanged
        }
    }

    private static func originalState(_ context: ModelContext, inventoryID: UUID,
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

    private static func fixtureLocation(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return ![URL.documentsDirectory, URL.applicationSupportDirectory].contains {
            path.starts(with: $0.resolvingSymlinksInPath().standardizedFileURL.pathComponents)
        }
    }

    /// Full zero-state inventory is deliberate until native operations exist.
    /// Never infer bootstrap metadata from a surviving graph or root marker.
    private static func emptyState(_ context: ModelContext, inventoryID: UUID,
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
              row.id == inventoryID, row.modeRaw == mode, row.phaseRaw == phase, row.cursor.isEmpty,
              row.storeIdentity == storeIdentity, row.rootIdentity == rootBinding, row.revision == 0,
              receipt.id == inventoryID, receipt.inventoryGeneration == row.generation,
              receipt.contractVersion == 1, receipt.revision == 0 else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}

struct SharedMediaNativeOriginalSnapshot: Equatable, Sendable {
    let inventory: SharedMediaStorageSnapshot
    let requiresRecovery: Bool
}

/// Registered before admission, so Auth can reach an in-flight open. This
/// qualification composition owns acquisition and settlement; live wiring stays disabled.
@MainActor
final class SharedMediaNativeOriginalOwner {
    private enum Phase { case unopened, opening, ready, failed, suspended }
    private let account: PhotoOriginalPreparationOwner.AccountAccess
    private let drain: SharedMediaNativeOriginalDrain
    private var registration: SharedMediaNativeOriginalDrain.Registration?
    private var phase = Phase.unopened
    private let writerEpoch = UUID()
    private var pendingSettlement: (request: SharedMediaAcquisitionIntent, loaderStarted: Bool)?
    private var storage: SharedMediaNativeStorageRepository?
    private var cancelActive: (() -> Void)?
    private var awaitActive: (() async -> Void)?

    private init(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain) {
        self.account = account; self.drain = drain
    }

    #if DEBUG
    static func qualification(account: PhotoOriginalPreparationOwner.AccountAccess,
                              drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        let owner = SharedMediaNativeOriginalOwner(account: account, drain: drain)
        owner.registration = try drain.register { [weak owner] in
            guard let owner else { return true }
            return await owner.invalidateAndAwaitForAccountTransition()
        }
        return owner
    }

    func open(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
              inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeOriginalSnapshot {
        guard phase == .unopened, let registration, drain.isCurrent(registration) else { throw SharedMediaStorageFailure.closed }
        phase = .opening
        do {
            return try await perform { [self] lease in
                let candidate = try SharedMediaNativeStorageRepository.originalAdmission(container: container,
                    authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot, inventoryID: inventoryID, ownerID: account.ownerID, writerEpoch: writerEpoch, pause: pause)
                storage = candidate
                let result = try await candidate.inspectOriginals { try self.check(lease) }
                try check(lease)
                phase = .ready
                return result
            }
        } catch {
            if phase != .suspended { phase = .failed }
            storage = nil
            throw error
        }
    }
    #endif

    func snapshot() async throws -> SharedMediaNativeOriginalSnapshot {
        guard phase == .ready else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try await storage.inspectOriginals { try self.check(lease) }
        }
    }

    #if DEBUG
    func setAcquisitionFault(_ fault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?) throws {
        guard (phase == .ready || phase == .suspended), cancelActive == nil, let storage else { throw SharedMediaStorageFailure.closed }
        storage.acquisitionFault = fault
    }
    #endif

    func prepareOriginal(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                         kind: SharedMediaAcquisitionIntent.Kind) async throws -> SharedMediaAcquisitionIntent {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals { try self.check(lease) }
            guard !snapshot.requiresRecovery else { throw PhotoPreparationFailure.cleanupPending }
            return try storage.originalRequest(packageID: packageID, draftGeneration: draftGeneration, ordinal: ordinal, kind: kind, epoch: writerEpoch)
        }
    }

    func acquireOriginal(_ request: SharedMediaAcquisitionIntent,
                         load: @escaping @Sendable () async throws -> Data) async throws -> SharedMediaAcquisitionResult {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] lease in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals { try self.check(lease) }
            if let existing = try storage.originalReceipt(request) {
                if case .completed(_, let result) = existing { return result }
                throw PhotoPreparationFailure.cleanupPending
            }
            guard !snapshot.requiresRecovery, request.writerEpoch == writerEpoch else { throw PhotoPreparationFailure.cleanupPending }
            try check(lease)
            var loaderStarted = false
            do {
                do { try storage.reserveOriginal(request) { try self.check(lease) } } catch { /* Exact saved-state recovery below. */ }
                guard case .reserved = try storage.originalReceipt(request) else { throw SharedMediaStorageFailure.conflict }
                let reserved = try storage.reservedState(request)
                try check(lease)
                // This is the sole loader invocation. Cold reservations never reach it.
                loaderStarted = true
                let data = try await storage.loadOriginal(load)
                try check(lease)
                guard try storage.reservedState(request) == reserved else { throw SharedMediaStorageFailure.stale }
                let proof = try await storage.writeOriginal(data, request: request)
                try check(lease)
                guard try storage.reservedState(request) == reserved else { throw SharedMediaStorageFailure.stale }
                do { try storage.completeOriginal(request, proof: proof) { try self.check(lease) } } catch { /* Exact saved-state recovery below. */ }
                guard case .completed(_, let result) = try storage.originalReceipt(request) else { throw SharedMediaStorageFailure.conflict }
                return result
            } catch {
                pendingSettlement = (request, loaderStarted)
                if let result = try? reconcileSettlement() { return result }
                throw error
            }
        }
    }

    /// Called only after the actual loader/file operation has returned. This
    /// settlement path deliberately does not reuse a cancelled dispatch check.
    private func reconcileSettlement() throws -> SharedMediaAcquisitionResult? {
        guard let pending = pendingSettlement, let storage else { return nil }
        if let saved = try storage.originalReceipt(pending.request) {
            switch saved {
            case .completed(_, let result): pendingSettlement = nil; return result
            case .held: pendingSettlement = nil
            case .reserved:
                do { try storage.holdOriginal(pending.request) } catch { /* Fresh exact readback below. */ }
                guard case .held = try storage.originalReceipt(pending.request) else { throw SharedMediaStorageFailure.conflict }
                pendingSettlement = nil
            case .released: throw SharedMediaStorageFailure.conflict
            }
        } else {
            guard !pending.loaderStarted else { throw SharedMediaStorageFailure.conflict }
            pendingSettlement = nil
        }
        return nil
    }

    private func check(_ lease: AccountBoundWorkLease) throws {
        guard phase == .opening || phase == .ready, let registration, drain.isCurrent(registration),
              lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
    }

    private func perform<T: Sendable>(_ body: @escaping @MainActor (AccountBoundWorkLease) async throws -> T) async throws -> T {
        guard cancelActive == nil, let registration, drain.isCurrent(registration) else { throw PhotoPreparationFailure.busy }
        let lease = try account.begin()
        do { try check(lease) } catch { account.finish(lease); throw error }
        let task = Task { @MainActor in
            defer { account.finish(lease); cancelActive = nil; awaitActive = nil }
            let result = try await body(lease)
            try check(lease)
            return result
        }
        cancelActive = { task.cancel() }
        awaitActive = { _ = await task.result }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard phase == .ready, drain.isCurrent(registration) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
        return result
    }

    func invalidateAndAwaitForAccountTransition() async -> Bool {
        phase = .suspended
        if let registration { drain.seal(registration) }
        cancelActive?()
        await awaitActive?()
        // Durable held settlement retains liability but permits process-fence
        // release after actual termination. Unknown settlement remains closed.
        do { _ = try reconcileSettlement() } catch { return false }
        guard pendingSettlement == nil else { return false }
        storage = nil
        return true
    }
}

/// Only the fenced native constructor can mint this immutable binding. No
/// decoding or raw-data factory is exposed outside this owner file.
struct SharedMediaNativeBinding: Sendable {
    let bytes: Data
    let initializing: Bool
    let epoch: UUID
    fileprivate init(bytes: Data, initializing: Bool, epoch: UUID) {
        self.bytes = bytes; self.initializing = initializing; self.epoch = epoch
    }
}

enum SharedMediaNativeInitializationBoundary: Sendable {
    case afterPhotoBinding, afterInboxBinding, afterAuthorityBinding, beforeSave, afterSave
}

/// Only this file's fenced repository can mint a synchronous save capability.
/// Retains the repository and checks account dispatch (or terminated-writer
/// settlement) plus fresh persistent root/store authority immediately before save.
@MainActor
struct SharedMediaNativeMutationAuthority {
    let binding: SharedMediaNativeBinding
    let ownerID: UUID
    let writerEpoch: UUID
    private let check: () throws -> Void
    fileprivate init(binding: SharedMediaNativeBinding, ownerID: UUID, writerEpoch: UUID, check: @escaping () throws -> Void) {
        self.binding = binding; self.ownerID = ownerID; self.writerEpoch = writerEpoch; self.check = check
    }
    func validate() throws { try check() }
}
