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
    private let originalIO: SharedMediaNativeOriginalIO
    private let inbox: SharedMediaInboxFiles
    private let inventoryID: UUID
    private let generation: UUID
    private let storeIdentity: String
    private let rootBinding: String
    private let binding: Data
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
                 originals: Bool = false, expectedOwnerID: UUID? = nil, pause: (@Sendable () async -> Void)? = nil) throws {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.invalid }
        let parent = authorityRoot.standardizedFileURL.deletingLastPathComponent()
        guard photoRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              inboxRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              configuration.url.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent() == parent,
              [authorityRoot, photoRoot, inboxRoot, configuration.url, configuration.url.deletingLastPathComponent()].allSatisfy(Self.fixtureLocation) else {
            throw SharedMediaStorageFailure.invalid
        }
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
                                              inboxRoot: URL, inventoryID: UUID, ownerID: UUID,
                                              pause: (@Sendable () async -> Void)?) throws -> SharedMediaNativeStorageRepository {
        try .init(container: container, authorityRoot: authorityRoot, photoRoot: photoRoot,
            inboxRoot: inboxRoot, inventoryID: inventoryID, fault: nil, originals: true, expectedOwnerID: ownerID, pause: pause)
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
/// first composition is read-only: acquisition mutations remain unavailable.
@MainActor
final class SharedMediaNativeOriginalOwner {
    private enum Phase { case unopened, opening, ready, failed, suspended }
    private let account: PhotoOriginalPreparationOwner.AccountAccess
    private let drain: SharedMediaNativeOriginalDrain
    private var registration: SharedMediaNativeOriginalDrain.Registration?
    private var phase = Phase.unopened
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
                    authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot, inventoryID: inventoryID, ownerID: account.ownerID, pause: pause)
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
        // Read-only admission has no writer to reconcile. The owned audit has
        // actually ended, so releasing retained descriptor owners is safe.
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
