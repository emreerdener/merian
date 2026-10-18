import CoreData
import Foundation
import SwiftData

/// Native-private, empty fixture-store admission. No media mutation, purge or
/// production composition is exposed until the closed native owners qualify.
@MainActor
final class SharedMediaNativeStorageRepository {
    private static let mode = "nativeQualificationV1"
    private static let phase = "readyNativeAccountingV1"
    private let container: ModelContainer
    private let files: SharedMediaStorageFileOwner
    private let photos: PhotoPreparationLockedFiles
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
                 inventoryID: UUID, fault: ((SharedMediaNativeInitializationBoundary) throws -> Void)?) throws {
        guard container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly, !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.invalid }
        let parent = authorityRoot.standardizedFileURL.deletingLastPathComponent()
        guard photoRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              inboxRoot.standardizedFileURL.deletingLastPathComponent() == parent,
              configuration.url.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent() == parent,
              [authorityRoot, photoRoot, inboxRoot, configuration.url, configuration.url.deletingLastPathComponent()].allSatisfy(Self.fixtureLocation) else {
            throw SharedMediaStorageFailure.invalid
        }
        self.container = container; self.inventoryID = inventoryID
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
        let existing = try Self.emptyState(context, inventoryID: inventoryID, storeIdentity: storeIdentity, rootBinding: rootBinding)
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
        _ = try snapshot()
    }

    /// Exact fresh read only. Nonempty native graphs remain unsupported here;
    /// an audit snapshot is not a constructor, writer or cleanup capability.
    func snapshot() throws -> SharedMediaStorageSnapshot {
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

/// Only the fenced native constructor can mint this immutable binding. No
/// decoding or raw-data factory is exposed outside this owner file.
struct SharedMediaNativeBinding {
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
