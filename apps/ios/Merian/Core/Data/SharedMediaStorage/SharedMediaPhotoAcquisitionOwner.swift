import Foundation
import SwiftData

/// Isolated original acquisition only. No live Capture composition, preparation,
/// transport, deletion, source handoff or admission to inference is exposed.
@MainActor
final class SharedMediaPhotoAcquisitionOwner {
    private let storage: SharedMediaStorageRepository
    private let io: SharedMediaPhotoIO
    private let account: PhotoOriginalPreparationOwner.AccountAccess
    private let epoch = UUID()
    private var suspended = false
    private var failed = false
    private var cancelActive: (() -> Void)?
    private var awaitActive: (() async -> Void)?

    init(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inventoryID: UUID,
         account: PhotoOriginalPreparationOwner.AccountAccess,
         inspection: PhotoPreparationDirectoryInspection = .init()) throws {
        storage = try SharedMediaStorageRepository(container: container, authorityRoot: authorityRoot,
            inventoryID: inventoryID, mode: .p1Qualification, sources: [SharedMediaPhotoLedger.namespace: photoRoot], photoInspection: inspection)
        guard let files = storage.photoFiles else { throw SharedMediaStorageFailure.closed }
        io = SharedMediaPhotoIO(files: files)
        self.account = account
    }

    #if DEBUG
    func setFault(_ fault: ((SharedMediaPhotoBoundary) throws -> Void)?) { storage.photoFault = fault }
    func setWriteFault(_ fault: (@Sendable (Int) throws -> Void)?) async { await io.setWriteFault(fault) }
    #endif

    private func check(_ lease: AccountBoundWorkLease) throws {
        guard !suspended, !failed, lease.session.userID == account.ownerID, account.isCurrent(lease) else {
            throw PhotoPreparationFailure.accountChanged
        }
        try Task.checkCancellation()
    }

    private func perform<T: Sendable>(_ body: @escaping @MainActor (AccountBoundWorkLease) async throws -> T) async throws -> T {
        guard !suspended, !failed, cancelActive == nil else { throw PhotoPreparationFailure.busy }
        let lease = try account.begin()
        do { try check(lease) } catch { account.finish(lease); throw error }
        let task = Task { @MainActor in
            defer { account.finish(lease); cancelActive = nil; awaitActive = nil }
            return try await body(lease)
        }
        cancelActive = { task.cancel() }
        awaitActive = { _ = await task.result }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func acquire(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                 maximumBytes: Int64 = PhotoPreparationPolicy.original,
                 load: @escaping @Sendable () async throws -> Data) async throws -> PhotoOriginalReference {
        let intent = PhotoPreparationIntent(leaseID: UUID(), ownerID: account.ownerID,
            packageID: packageID, assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(),
            draftGeneration: draftGeneration, processEpoch: epoch, role: .original,
            ordinal: ordinal, acquisitionKind: "sharedQualification", maximumBytes: maximumBytes)
        return try await perform { [self] lease in
            let inventory = try storage.photoInventory()
            guard !inventory.hasPending else { throw PhotoPreparationFailure.cleanupPending }
            try await io.validate(inventory)
            try await io.preflight()
            try check(lease)
            do {
                // A save exception can mean lost acknowledgement. Only exact
                // fresh readback permits this controller's first callback.
                do { try storage.reservePhoto(intent) } catch { /* reconcile below */ }
                try storage.requirePhotoReservation(intent)
                try check(lease)
                let data = try await io.load(load)
                try check(lease)
                let proof = try await io.write(data, intent: intent)
                try check(lease)
                do { try storage.commitPhoto(intent, proof: proof) } catch { /* reconcile below */ }
                let handle = try storage.completedPhoto(intent, file: proof.file)
                try check(lease)
                return handle
            } catch {
                // Never assume rollback or repeat the provider. A committed
                // state remains materialized; unresolved work retains its max.
                try? storage.holdPhoto(intent)
                failed = true
                throw error
            }
        }
    }

    /// Restores only jointly committed handles. Pending intent cannot supply a
    /// handle or authorize callback replay, lease closure or capacity release.
    func recover() async throws -> SharedMediaPhotoRecovery {
        try await perform { [self] lease in
            let inventory = try storage.photoInventory()
            try await io.validate(inventory)
            try check(lease)
            return SharedMediaPhotoRecovery(originals: inventory.originals.filter { $0.ownerID == account.ownerID },
                requiresRecovery: inventory.hasPending)
        }
    }

    func originalData(_ handle: PhotoOriginalReference) async throws -> Data {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        return try await perform { [self] lease in
            let file = try storage.resolvePhoto(handle)
            let inventory = try storage.photoInventory()
            guard let identity = inventory.identities[file.assetID] else { throw SharedMediaStorageFailure.conflict }
            let data = try await io.read(file, identity: identity)
            try check(lease)
            return data
        }
    }

    func invalidateAndAwaitForAccountTransition() async -> Bool {
        suspended = true
        cancelActive?()
        await awaitActive?()
        return !failed
    }
}

/// Image/hash/file work stays off the main actor. The shared repository retains
/// its exclusive store/root fences throughout every awaited callback and I/O.
private actor SharedMediaPhotoIO {
    private let files: PhotoPreparationLockedFiles
    init(files: PhotoPreparationLockedFiles) { self.files = files }

    func validate(_ inventory: SharedMediaPhotoInventory) throws {
        try files.checkInventory(knownTokens: Set(inventory.files.map(\.token)).union(inventory.pendingTokens))
        for file in inventory.files {
            guard try files.verifiedIdentity(file) == inventory.identities[file.assetID] else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    #if DEBUG
    func setWriteFault(_ fault: (@Sendable (Int) throws -> Void)?) { files.sharedWriteFault = fault }
    #endif
    func preflight() throws { try files.checkFreeSpace() }
    func load(_ provider: @Sendable () async throws -> Data) async throws -> Data { try await provider() }
    func write(_ data: Data, intent: PhotoPreparationIntent) throws -> SharedMediaPhotoFileProof {
        try files.sharedProof(files.write(data, intent: intent))
    }
    func read(_ file: PhotoPreparationFile, identity: String) throws -> Data {
        guard try files.verifiedIdentity(file) == identity else { throw SharedMediaStorageFailure.conflict }
        return try files.read(file)
    }
}

struct SharedMediaPhotoRecovery: Sendable {
    let originals: [PhotoOriginalReference]
    let requiresRecovery: Bool
}
