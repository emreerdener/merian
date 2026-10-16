import Foundation
import SwiftData

/// Sole P1 writer. No funding, network, upload or queue dependency exists here.
@MainActor
final class PhotoOriginalPreparationOwner {
    struct AccountAccess {
        let ownerID: UUID
        let begin: @MainActor () throws -> AccountBoundWorkLease
        let isCurrent: @MainActor (AccountBoundWorkLease) -> Bool
        let finish: @MainActor (AccountBoundWorkLease) -> Void
    }

    let repository: PhotoPreparationRepository
    let files: PhotoPreparationFileStore
    let account: AccountAccess
    private let processEpoch = UUID()
    private var suspended = false
    private var cancelActive: (() -> Void)?
    private var awaitActive: (() async -> Void)?
    private var pauseFailed = false

    private init(container: ModelContainer, root: URL, account: AccountAccess) {
        repository = PhotoPreparationRepository(container: container)
        files = PhotoPreparationFileStore(root: root)
        self.account = account
    }

    /// Explicit qualification composition only. Production dependencies are nil.
    static func qualification(container: ModelContainer, root: URL, account: AccountAccess,
                              competingAllocators: [String] = []) throws -> PhotoOriginalPreparationOwner {
        guard competingAllocators.isEmpty,
              !root.standardizedFileURL.path.hasPrefix(URL.documentsDirectory.standardizedFileURL.path + "/"),
              root.standardizedFileURL != URL.documentsDirectory.standardizedFileURL else {
            throw PhotoPreparationFailure.unsupportedComposition
        }
        return PhotoOriginalPreparationOwner(container: container, root: root, account: account)
    }

    static func syntheticAccount(ownerID: UUID, runtime: AuthRuntimeState) -> AccountAccess {
        let session = AuthTransitionSession(userID: ownerID, isAnonymous: false)
        return AccountAccess(ownerID: ownerID,
            begin: { runtime.beginAccountWork(session: session) },
            isCurrent: { runtime.accountWorkLeaseIsCurrent($0, publishedSession: session, sdkSession: session) },
            finish: { _ = runtime.finishAccountWork($0) })
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (PhotoPreparationLockedFiles, AccountBoundWorkLease) async throws -> T
    ) async throws -> T {
        guard !suspended, cancelActive == nil else { throw PhotoPreparationFailure.busy }
        let lease = try account.begin()
        guard lease.session.userID == account.ownerID, account.isCurrent(lease) else {
            account.finish(lease)
            throw PhotoPreparationFailure.accountChanged
        }
        let task = Task { @MainActor in
            defer {
                account.finish(lease)
                cancelActive = nil
                awaitActive = nil
            }
            return try await files.locked { locked in try await operation(locked, lease) }
        }
        cancelActive = { task.cancel() }
        awaitActive = { _ = await task.result }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func checkAccount(_ lease: AccountBoundWorkLease) throws {
        guard !suspended, account.isCurrent(lease), lease.session.userID == account.ownerID else {
            throw PhotoPreparationFailure.accountChanged
        }
    }

    private func knownTokens() throws -> Set<String> {
        let known = try repository.knownFiles()
        return Set(known.files.map(\.token) + known.pending)
    }

    func acquire(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                 sourceKind: String, maximumBytes: Int64 = PhotoPreparationPolicy.original,
                 sourceByteLiability: Int64 = 0, sourceIdentity: String? = nil,
                 load: @escaping @Sendable () async throws -> Data) async throws -> PhotoOriginalReference {
        let intent = PhotoPreparationIntent(leaseID: UUID(), ownerID: account.ownerID, packageID: packageID,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), draftGeneration: draftGeneration,
            processEpoch: processEpoch, role: .original, ordinal: ordinal,
            acquisitionKind: sourceKind, maximumBytes: maximumBytes, sourceByteLiability: sourceByteLiability, sourceIdentity: sourceIdentity)
        return try await store(intent, load: load)
    }

    private func store(_ intent: PhotoPreparationIntent,
                       load: @escaping @Sendable () async throws -> Data) async throws -> PhotoOriginalReference {
        try await perform { [self] files, lease in
            try files.checkInventory(knownTokens: await knownTokens())
            try files.checkFreeSpace()
            try await repository.reserve(intent)
            do {
                let data = try await load()
                try Task.checkCancellation()
                try await checkAccount(lease)
                let written = try files.write(data, intent: intent)
                try await checkAccount(lease)
                return try await repository.commit(intent, file: written)
            } catch {
                do { try await repository.markUncertain(packageID: intent.packageID) }
                catch { await markPauseFailed() }
                throw error
            }
        }
    }

    private func markPauseFailed() { pauseFailed = true }

    func storeDerivative(_ data: Data, for handle: PhotoOriginalReference,
                         role: PhotoPreparationRole, ordinal: Int64) async throws {
        guard role != .original, handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.invalidMedia }
        // Original resolution and revision validation are repeated inside the lock.
        let intent = PhotoPreparationIntent(leaseID: UUID(), ownerID: account.ownerID, packageID: handle.packageID,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), draftGeneration: handle.draftGeneration,
            processEpoch: processEpoch, role: role, ordinal: ordinal, acquisitionKind: "prepared",
            maximumBytes: Int64(data.count))
        _ = try await perform { [self] files, lease in
            _ = try await repository.resolve(handle)
            try files.checkInventory(knownTokens: await knownTokens())
            try files.checkFreeSpace()
            try await repository.reserve(intent)
            do {
                try await checkAccount(lease)
                let written = try files.write(data, intent: intent)
                try await checkAccount(lease)
                return try await repository.commit(intent, file: written)
            } catch {
                do { try await repository.markUncertain(packageID: intent.packageID) }
                catch { await markPauseFailed() }
                throw error
            }
        }
    }

    func prepare<T: Sendable>(_ handle: PhotoOriginalReference,
                              using prepare: @escaping @Sendable (URL) async throws -> T) async throws -> T {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        return try await perform { [self] files, lease in
            let file = try await repository.resolve(handle)
            let url = try files.preparationURL(file)
            let result = try await prepare(url)
            try files.verify(file)
            try await checkAccount(lease)
            return result
        }
    }

    func updateDerivatives(for handle: PhotoOriginalReference, ai: Data, display: Data) async throws {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        try await perform { [self] files, lease in
            try files.checkInventory(knownTokens: await knownTokens())
            try files.checkFreeSpace()
            let ordinal = try await repository.retireDerivatives(handle)
            let tokens = try await repository.cleanupTokens()
            for token in tokens { try files.unlink(token) }
            try await repository.finishCleanup(tokens: tokens)
            for (role, data) in [(PhotoPreparationRole.aiInput, ai), (.display, display)] {
                let intent = PhotoPreparationIntent(leaseID: UUID(), ownerID: handle.ownerID, packageID: handle.packageID,
                    assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), draftGeneration: handle.draftGeneration,
                    processEpoch: processEpoch, role: role, ordinal: ordinal, acquisitionKind: "prepared", maximumBytes: Int64(data.count))
                try await repository.reserve(intent)
                do {
                    try await checkAccount(lease)
                    let written = try files.write(data, intent: intent)
                    try await checkAccount(lease)
                    _ = try await repository.commit(intent, file: written)
                } catch {
                    do { try await repository.markUncertain(packageID: intent.packageID) }
                    catch { await markPauseFailed() }
                    throw error
                }
            }
        }
    }

    func remove(_ handle: PhotoOriginalReference) async throws {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        try await perform { [self] files, lease in
            try files.checkInventory(knownTokens: await knownTokens())
            try await checkAccount(lease)
            try await repository.removeOriginal(handle)
            let tokens = try await repository.cleanupTokens()
            for token in tokens { try files.unlink(token) }
            try await repository.finishCleanup(tokens: tokens)
        }
    }

    func originalData(_ handle: PhotoOriginalReference) async throws -> Data {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        return try await perform { [self] files, lease in
            let file = try await repository.resolve(handle)
            try await checkAccount(lease)
            return try files.read(file)
        }
    }

    func derivativeData(_ handle: PhotoOriginalReference) async throws -> (Data, Data) {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        return try await perform { [self] files, lease in
            let pair = try await repository.derivatives(handle)
            try await checkAccount(lease)
            return try (files.read(pair.0), files.read(pair.1))
        }
    }

    func releaseSource(_ handle: PhotoOriginalReference, identity: String,
                       releaseAndConfirm: @escaping @Sendable () async throws -> Void) async throws {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        try await perform { [self] _, lease in
            try await checkAccount(lease)
            try await repository.validateSourceRelease(handle, identity: identity)
            try await releaseAndConfirm()
            try await checkAccount(lease)
            try await repository.confirmSourceRelease(handle, identity: identity)
        }
    }

    /// The caller is the existing inbox owner and must durably acknowledge
    /// accepting the source liability. Timeouts and namespace locks are not ACKs.
    func returnSource(packageID: UUID, identity: String,
                      acknowledgeReturn: @escaping @Sendable () async throws -> Void) async throws {
        try await perform { [self] _, lease in
            try await checkAccount(lease)
            let sourceLease = try await repository.validateSourceReturn(packageID: packageID,
                ownerID: account.ownerID, identity: identity)
            try await acknowledgeReturn()
            try await checkAccount(lease)
            try await repository.confirmSourceReturn(packageID: packageID, ownerID: account.ownerID,
                identity: identity, leaseID: sourceLease)
        }
    }

    func saveContexts(packageID: UUID, revision: Int64, contexts: [ObservationContext], presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> Int64 {
        try await perform { [self] _, lease in
            try await checkAccount(lease)
            return try await repository.saveContexts(packageID: packageID, ownerID: account.ownerID,
                expectedRevision: revision, contexts: contexts, presentation: presentation)
        }
    }

    func freeze(_ snapshot: PhotoPreparationSnapshot) async throws -> PhotoPreparationReceipt {
        try await perform { [self] files, lease in
            try files.checkInventory(knownTokens: await knownTokens())
            let cohort = try await repository.filesForFreeze(snapshot, ownerID: account.ownerID)
            for file in cohort { try files.verify(file) }
            try await checkAccount(lease)
            return try await repository.freeze(snapshot, ownerID: account.ownerID)
        }
    }

    func recover() async throws -> [PhotoPreparationDraft] {
        try await perform { [self] files, lease in
            try files.checkInventory(knownTokens: await knownTokens())
            try await repository.reconcileClosedWriters()
            let known = try await repository.filesToRecover()
            for file in known {
                do { try files.verify(file) }
                catch PhotoPreparationFailure.missingMedia { try await repository.markMissing(assetID: file.assetID) }
            }
            try await checkAccount(lease)
            return try await repository.recovery(ownerID: account.ownerID)
        }
    }

    func discard(packageID: UUID, revision: Int64) async throws {
        try await perform { [self] files, lease in
            try files.checkInventory(knownTokens: await knownTokens())
            try await checkAccount(lease)
            try await repository.retire(packageID: packageID, ownerID: account.ownerID, expectedRevision: revision)
            let tokens = try await repository.cleanupTokens()
            for token in tokens { try files.unlink(token) }
            try await repository.finishCleanup(tokens: tokens)
        }
    }

    func shareOriginal(_ handle: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) async throws -> PhotoOriginalReference {
        guard handle.ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        return try await perform { [self] files, lease in
            let original = try await repository.resolve(handle)
            try files.verify(original)
            try await checkAccount(lease)
            return try await repository.shareOriginal(handle, packageID: packageID, draftGeneration: draftGeneration)
        }
    }

    func purge() async throws {
        guard await invalidateAndAwaitForAccountTransition() else { throw PhotoPreparationFailure.cleanupPending }
        try await files.locked { [self] files in
            try files.checkInventory(knownTokens: await knownTokens())
            try await repository.retireAll()
            let tokens = try await repository.cleanupTokens()
            for token in tokens { try files.unlink(token) }
            try files.removeEmptyNamespace()
            try await repository.finishCleanup(tokens: tokens)
        }
        // Remains suspended: the owning library transition must explicitly
        // construct a new generation, never reopen admission as a cleanup effect.
    }

    func invalidateAndAwaitForAccountTransition() async -> Bool {
        suspended = true
        cancelActive?()
        await awaitActive?()
        return !pauseFailed
    }
}
