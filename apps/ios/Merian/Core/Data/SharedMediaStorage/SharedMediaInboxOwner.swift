import Foundation
import SwiftData

/// Explicit isolated composition only. Source operations are device-local and
/// accountless. The single task retains every fence through cancellation drain.
@MainActor
final class SharedMediaInboxOwner {
    private let storage: SharedMediaStorageRepository
    private let io: SharedMediaInboxIO
    private let destinationIO: SharedMediaInboxDestinationIO
    private var active: (() async -> Void)?
    private var cancel: (() -> Void)?
    private var suspended = false
    private var purgeInProgress = false
    private let purgeCoordinatorID: UUID

    convenience init(container: ModelContainer, authorityRoot: URL, inboxRoot: URL, photoRoot: URL, inventoryID: UUID) throws {
        try self.init(container: container, authorityRoot: authorityRoot, inboxRoot: inboxRoot, photoRoot: photoRoot, inventoryID: inventoryID, resumePurgeID: nil)
    }
    static func resumePurge(id: UUID, container: ModelContainer, authorityRoot: URL, inboxRoot: URL, photoRoot: URL, inventoryID: UUID) throws -> SharedMediaInboxOwner {
        try .init(container: container, authorityRoot: authorityRoot, inboxRoot: inboxRoot, photoRoot: photoRoot, inventoryID: inventoryID, resumePurgeID: id)
    }
    private init(container: ModelContainer, authorityRoot: URL, inboxRoot: URL, photoRoot: URL, inventoryID: UUID, resumePurgeID: UUID?) throws {
        let coordinator = UUID(); purgeCoordinatorID = coordinator; suspended = resumePurgeID != nil
        storage = try SharedMediaStorageRepository(container: container, authorityRoot: authorityRoot,
            inventoryID: inventoryID, mode: .p1InboxQualification,
            sources: [SharedMediaInboxFiles.namespace: inboxRoot, SharedMediaPhotoLedger.namespace: photoRoot],
            purgeCoordinatorID: coordinator, resumePurgeID: resumePurgeID)
        guard let files = storage.inboxFiles else { throw SharedMediaStorageFailure.closed }
        io = SharedMediaInboxIO(files: files)
        guard let destination = storage.photoFiles else { throw SharedMediaStorageFailure.closed }
        destinationIO = SharedMediaInboxDestinationIO(files: destination)
    }

    #if DEBUG
    func setPurgeFault(_ fault: ((SharedMediaPurgeBoundary) throws -> Void)?) { storage.setPurgeFault(fault) }
    func setPurgeReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async { await destinationIO.setOriginalReleaseFault(fault) }
    func setHandoffAvailableBytes(_ value: Int64?) { storage.handoffAvailableBytes = value }
    func setHandoffPause(_ pause: (@Sendable () async -> Void)?) async { await destinationIO.setPause(pause) }
    func setHandoffFault(_ fault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?) { storage.handoffFault = fault }
    func setHandoffFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async { await destinationIO.setFault(fault) }
    func setFault(_ fault: ((SharedMediaInboxBoundary) throws -> Void)?) { storage.inboxFault = fault }
    func setFileFault(_ fault: (@Sendable (SharedMediaInboxBoundary) throws -> Void)?) async { await io.setFault(fault) }
    #endif

    private func perform<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        guard active == nil, !suspended else { throw SharedMediaStorageFailure.busy }
        let task = Task { @MainActor in
            defer { active = nil; cancel = nil }
            return try await body()
        }
        active = { _ = await task.result }; cancel = { task.cancel() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func stage(maximumBytes: Int64 = PhotoPreparationPolicy.original,
               load: @escaping @Sendable () async throws -> Data) async throws -> SharedMediaInboxHandle {
        try await perform { [self] in
            let sources = try storage.inboxSources()
            try await io.validate(sources)
            try await destinationIO.validate(storage.inboxRead { try $0.photos.inventory() })
            for source in sources where source.writerState == "closed" && source.phase != "retiring" {
                try await reconcileOccupancy(source)
            }
            try Task.checkCancellation()
            let id = UUID(), generation = UUID(), work = UUID()
            var source = try transaction(before: .beforeReservationSave, after: .afterReservationSave) {
                try $0.reserve(id: id, generation: generation, workID: work, maximumBytes: maximumBytes)
            }
            do {
                try Task.checkCancellation()
                let data = try await io.load(load)
                try Task.checkCancellation()
                let facts = try await io.prepare(data, maximum: maximumBytes)
                source = try transaction(before: .beforePreparedSave, after: .afterPreparedSave) { try $0.prepare(source, facts: facts) }
                let partial = try await io.begin(source)
                source = try transaction(before: .beforeIdentitySave, after: .afterIdentitySave) { try $0.recordPartial(source, identity: partial) }
                let proof = try await io.write(data, source: source)
                try Task.checkCancellation()
                return try transaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.complete(proof) }.handle
            } catch {
                // Callback and actor work have returned. No callback retry is
                // authorized, even if the save acknowledgement was lost.
                if let latest = try? current(id: id, generation: generation), latest.phase != "ready" {
                    if let closed = try? closeWriter(latest) { try? await reconcileOccupancy(closed) }
                }
                throw error
            }
        }
    }

    func catalog() throws -> [SharedMediaInboxHandle] {
        guard active == nil else { throw SharedMediaStorageFailure.busy }
        return try storage.inboxSources().filter { $0.phase == "ready" }.map(\.handle)
    }

    func originalData(_ handle: SharedMediaInboxHandle) async throws -> Data {
        try await perform { [self] in
            let source = try storage.inboxSource(handle)
            return try await io.read(source)
        }
    }

    func recover() async throws -> [SharedMediaInboxRecovery] {
        try await perform { [self] in
            let sources = try storage.inboxSources()
            try await io.validate(sources)
            try await destinationIO.validate(storage.inboxRead { try $0.photos.inventory() })
            var result: [SharedMediaInboxRecovery] = []
            for initial in sources {
                try Task.checkCancellation()
                var source = initial
                if source.phase == "retiring" {
                    try await finishRetirement(source.handle)
                    continue
                }
                source = try closeWriter(source)
                do {
                    try await reconcileOccupancy(source)
                    if let proof = try await io.recover(source) {
                        let complete = try transaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.complete(proof) }
                        result.append(.ready(complete.handle))
                    } else {
                        result.append(source.phase == "ready" ? .missing(source.handle) : .incomplete(source.handle))
                    }
                } catch { result.append(.conflict(source.handle)) }
            }
            return result
        }
    }

    func discard(_ handle: SharedMediaInboxHandle) async throws {
        try await perform { [self] in
            try await io.validate(storage.inboxSources())
            var source = try storage.inboxSource(handle)
            if source.phase != "retiring" {
                source = try closeWriter(source)
                let inspection = try await io.inspectRetirement(source)
                source = try transaction(before: .beforeRetirementSave, after: .afterRetirementSave) { try $0.retire(inspection) }
            }
            try await finishRetirement(source.handle)
        }
    }

    func prepareHandoff(_ source: SharedMediaInboxHandle, account: PhotoOriginalPreparationOwner.AccountAccess,
                        packageID: UUID, draftGeneration: UUID, ordinal: Int64 = 0) throws -> SharedMediaInboxHandoffRequest {
        guard active == nil, !suspended else { throw SharedMediaStorageFailure.busy }
        let lease = try account.begin(); defer { account.finish(lease) }
        try check(account, lease)
        return try storage.inboxRead { try $0.handoffs.prepare($0.source(source), ownerID: account.ownerID,
            packageID: packageID, draftGeneration: draftGeneration, ordinal: ordinal) }
    }

    func handoff(_ request: SharedMediaInboxHandoffRequest,
                 account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> PhotoOriginalReference {
        try await accountOperation(account, ownerID: request.ownerID) { [self] lease in
            // Saved state is recovery only. Never resume an incomplete write by
            // rereading the source or issuing a replacement request.
            if let saved = try handoffState(request) {
                guard saved.completed else { throw PhotoPreparationFailure.cleanupPending }
                guard let proof = try await destinationIO.recover(saved) else { throw PhotoPreparationFailure.missingMedia }
                try check(account, lease)
                _ = try handoffTransaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.handoffs.complete(proof) }
                try check(account, lease); return request.handle
            }
            try await destinationIO.validate(storage.inboxRead { try $0.photos.inventory() }); try check(account, lease)
            var state = try handoffTransaction(before: .beforeReservationSave, after: .afterReservationSave, requiresFreeSpace: true) {
                try $0.handoffs.reserve(request)
            }
            do {
                let source = try storage.inboxSource(request.source)
                let data = try await io.read(source); try check(account, lease)
                let partial = try await destinationIO.begin(state); try check(account, lease)
                state = try handoffTransaction(before: .beforeIdentitySave, after: .afterIdentitySave) { try $0.handoffs.partial(partial) }
                let proof = try await destinationIO.write(data, state: state); try check(account, lease)
                _ = try await io.read(source); try check(account, lease)
                _ = try handoffTransaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.handoffs.complete(proof) }
                try check(account, lease); return request.handle
            } catch {
                // Both actor calls have returned. Closing the local writer is
                // accountless and retains all liabilities if proof cannot form.
                if let current = try? handoffState(request) { _ = try? await closeHandoff(current) }
                throw error
            }
        }
    }

    func recoverHandoffs(account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> [SharedMediaInboxHandoffRecovery] {
        try await accountOperation(account, ownerID: account.ownerID) { [self] lease in
            try await destinationIO.prune(storage.inboxRead { try $0.photos.inventory() }); try check(account, lease)
            let states = try storage.inboxRead { try $0.handoffs.all() }.filter { $0.request.ownerID == account.ownerID }
            var result: [SharedMediaInboxHandoffRecovery] = []
            for initial in states {
                try check(account, lease)
                if initial.detached { result.append(.detached(initial.request)); continue }
                if initial.phase == "sourceRetiring" {
                    // This irreversible intent is already pinned and may be
                    // completed by the source owner even after account change.
                    let source = try storage.inboxSources().first { $0.handle.id == initial.request.source.id }
                    guard let source else { throw SharedMediaStorageFailure.conflict }
                    try await finishRetirement(source.handle); try check(account, lease)
                    result.append(.completed(initial.request, initial.request.handle)); continue
                }
                do {
                    let state = try await closeHandoff(initial); try check(account, lease)
                    if let proof = try await destinationIO.recover(state) {
                        try check(account, lease)
                        _ = try handoffTransaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.handoffs.complete(proof) }
                        result.append(.completed(state.request, state.request.handle))
                    } else { try check(account, lease); result.append(.incomplete(state.request)) }
                } catch {
                    try check(account, lease); result.append(.conflict(initial.request))
                }
            }
            return result
        }
    }

    func abandonHandoff(_ request: SharedMediaInboxHandoffRequest) async throws {
        try await perform { [self] in
            guard let initial = try handoffState(request) else { throw SharedMediaStorageFailure.stale }
            if initial.detached { return }
            let closed = try await closeHandoff(initial)
            let proof = try await destinationIO.closure(closed)
            do {
                try storage.handoffWrite(before: .beforeAbandonSave, after: .afterAbandonSave) {
                    try $0.handoffs.abandon(proof)
                }
            } catch {
                if let saved = try handoffState(request), !saved.detached { throw error }
            }
        }
    }

    func retireHandoffSource(_ request: SharedMediaInboxHandoffRequest,
                             account: PhotoOriginalPreparationOwner.AccountAccess) async throws {
        try await accountOperation(account, ownerID: request.ownerID) { [self] lease in
            guard let state = try handoffState(request) else { throw SharedMediaStorageFailure.stale }
            if state.phase != "sourceRetiring" {
                guard state.completed, let proof = try await destinationIO.recover(state) else { throw PhotoPreparationFailure.cleanupPending }
                try check(account, lease)
                _ = try handoffTransaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.handoffs.complete(proof) }
                let source = try storage.inboxSource(request.source)
                let inspection = try await io.inspectRetirement(source); try check(account, lease)
                _ = try transaction(before: .beforeRetirementSave, after: .afterRetirementSave) { try $0.retireHandoff(inspection, request: request) }
            }
            guard let source = try storage.inboxSources().first(where: { $0.handle.id == request.source.id }) else { throw SharedMediaStorageFailure.stale }
            try await finishRetirement(source.handle)
        }
    }

    func discardDetachedHandoff(_ request: SharedMediaInboxHandoffRequest,
                                account: PhotoOriginalPreparationOwner.AccountAccess) async throws {
        try await accountOperation(account, ownerID: request.ownerID) { [self] lease in
            guard let state = try handoffState(request), state.detached else { throw SharedMediaStorageFailure.stale }
            if state.phase == "detached" {
                let inspection = try await destinationIO.inspectRetirement(state); try check(account, lease)
                _ = try handoffTransaction(before: .beforeRetirementSave, after: .afterRetirementSave) { try $0.handoffs.retireDetached(inspection) }
            }
            let intent = try storage.detachedRetirement(request)
            try check(account, lease)
            let proof = try await destinationIO.release(intent)
            try check(account, lease)
            do { try storage.handoffWrite(before: .beforeReleaseSave, after: .afterReleaseSave) { try $0.handoffs.releaseDetached(proof) } } catch { guard try handoffState(request) == nil else { throw error } }
            try await destinationIO.prune(storage.inboxRead { try $0.photos.inventory() }); try check(account, lease)
        }
    }

    func destinationOriginalData(_ handle: PhotoOriginalReference,
                                 account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> Data {
        try await accountOperation(account, ownerID: handle.ownerID) { [self] lease in
            let (file, identity) = try storage.inboxRead { ledger in
                let file = try ledger.photos.resolve(handle), inventory = try ledger.photos.inventory()
                guard let identity = inventory.identities[file.assetID] else { throw SharedMediaStorageFailure.conflict }
                return (file, identity)
            }
            let bytes = try await destinationIO.read(file, identity: identity); try check(account, lease)
            return bytes
        }
    }

    func prepareDerivatives(_ original: PhotoOriginalReference, ai: Data, display: Data,
                            account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> SharedMediaDerivativeRequest {
        try await accountOperation(account, ownerID: original.ownerID) { [self] lease in
            try await derivatives(account, lease).prepare(original, ai: ai, display: display)
        }
    }

    func replaceDerivatives(_ request: SharedMediaDerivativeRequest, ai: Data, display: Data,
                            account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> SharedMediaDerivativeReceipt {
        try await accountOperation(account, ownerID: request.original.ownerID) { [self] lease in
            try await derivatives(account, lease).replace(request, ai: ai, display: display)
        }
    }

    func readyDerivatives(_ request: SharedMediaDerivativeRequest,
                          account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> SharedMediaDerivativeReceipt {
        try await accountOperation(account, ownerID: request.original.ownerID) { [self] lease in
            try await derivatives(account, lease).ready(request)
        }
    }

    func recoverDerivatives(account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> [SharedMediaDerivativeRecovery] {
        try await accountOperation(account, ownerID: account.ownerID) { [self] lease in
            try await derivatives(account, lease).recover(ownerID: account.ownerID)
        }
    }

    func discardDerivatives(_ request: SharedMediaDerivativeRequest,
                            account: PhotoOriginalPreparationOwner.AccountAccess) async throws {
        try await accountOperation(account, ownerID: request.original.ownerID) { [self] lease in
            try await derivatives(account, lease).discard(request)
        }
    }

    func saveDraftMetadata(packageID: UUID, revision: Int64, contexts: [ObservationContext],
                           presentation: [PhotoPreparationImagePresentation]? = nil,
                           account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> Int64 {
        try await accountOperation(account, ownerID: account.ownerID) { [self] lease in
            try drafts(account, lease).saveMetadata(packageID: packageID, ownerID: account.ownerID,
                revision: revision, contexts: contexts, presentation: presentation)
        }
    }

    func draftCatalog(account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> [PhotoPreparationDraft] {
        try await accountOperation(account, ownerID: account.ownerID) { [self] lease in
            let result = try storage.inboxRead { try $0.drafts.catalog(ownerID: account.ownerID) }
            try check(account, lease); return result
        }
    }

    func prepareFreeze(_ snapshot: PhotoPreparationSnapshot,
                       account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> SharedMediaFreezeRequest {
        try await accountOperation(account, ownerID: account.ownerID) { [self] lease in
            try await drafts(account, lease).prepare(snapshot, ownerID: account.ownerID)
        }
    }

    func freeze(_ request: SharedMediaFreezeRequest,
                account: PhotoOriginalPreparationOwner.AccountAccess) async throws -> PhotoPreparationReceipt {
        try await accountOperation(account, ownerID: account.ownerID) { [self] lease in
            try await drafts(account, lease).freeze(request, ownerID: account.ownerID)
        }
    }

    private func drafts(_ account: PhotoOriginalPreparationOwner.AccountAccess,
                        _ lease: AccountBoundWorkLease) -> SharedMediaDraftOperations {
        .init(storage: storage, io: destinationIO, check: { [self] in try check(account, lease) })
    }

    private func derivatives(_ account: PhotoOriginalPreparationOwner.AccountAccess,
                             _ lease: AccountBoundWorkLease) -> SharedMediaDerivativeOperations {
        .init(storage: storage, io: destinationIO, check: { [self] in try check(account, lease) })
    }

    private func accountOperation<T: Sendable>(_ account: PhotoOriginalPreparationOwner.AccountAccess, ownerID: UUID,
                                               _ body: @escaping @MainActor (AccountBoundWorkLease) async throws -> T) async throws -> T {
        guard ownerID == account.ownerID else { throw PhotoPreparationFailure.accountChanged }
        return try await perform { [self] in
            let lease = try account.begin(); defer { account.finish(lease) }
            try check(account, lease); return try await body(lease)
        }
    }

    private func check(_ account: PhotoOriginalPreparationOwner.AccountAccess, _ lease: AccountBoundWorkLease) throws {
        guard !suspended, account.ownerID == lease.session.userID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
    }

    private func handoffState(_ request: SharedMediaInboxHandoffRequest) throws -> SharedMediaInboxHandoff? {
        try storage.inboxRead { try $0.handoffs.saved(request) }
    }

    private func closeHandoff(_ state: SharedMediaInboxHandoff) async throws -> SharedMediaInboxHandoff {
        let proof = try await destinationIO.closure(state)
        return try handoffTransaction(before: .beforeClosureSave, after: .afterClosureSave) { try $0.handoffs.close(proof) }
    }

    private func handoffTransaction(before: SharedMediaInboxHandoffBoundary, after: SharedMediaInboxHandoffBoundary,
                                    requiresFreeSpace: Bool = false,
                                    _ body: (SharedMediaInboxLedger) throws -> SharedMediaInboxHandoff) throws -> SharedMediaInboxHandoff {
        var expected: SharedMediaInboxHandoff?
        do {
            return try storage.handoffWrite(before: before, after: after, requiresFreeSpace: requiresFreeSpace) {
                let value = try body($0); expected = value; return value
            }
        } catch {
            guard let expected, try handoffState(expected.request) == expected else { throw error }
            return expected
        }
    }

    func validatePurgeTarget(in context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try storage.requirePurgeContainer(context.container)
    }

    /// Explicit whole-library reset only. No production caller is composed.
    /// The same stable reset ID is required for restart/lost-ack recovery.
    func purgeWholeLibrary(resetID: UUID, afterAdmissionClosed: @MainActor () async throws -> Void = {}) async throws -> SharedMediaPurgeCompletion {
        guard !purgeInProgress else { throw SharedMediaStorageFailure.busy }
        purgeInProgress = true; suspended = true
        defer { purgeInProgress = false }
        do { try storage.beginPurge(id: resetID) } catch { try storage.beginPurge(id: resetID) } // Exact saved intent only.
        cancel?(); if let active { await active() }
        guard active == nil else { throw SharedMediaStorageFailure.busy }
        try await afterAdmissionClosed()
        let drained = SharedMediaPurgeDrain(coordinatorID: purgeCoordinatorID)
        let access: SharedMediaPurgeAccess
        do { access = try storage.purgeAccess(id: resetID, drained: drained) } catch { access = try storage.purgeAccess(id: resetID, drained: drained) }
        let task = Task { @MainActor [self] in
            defer { active = nil; cancel = nil }
            let operations = SharedMediaPurgeOperations(storage: storage, sourceIO: io, destinationIO: destinationIO, access: access,
                closeSource: { [self] source in .init(source: source, epoch: storage.inboxEpoch) })
            return try await operations.run()
        }
        active = { _ = await task.result }; cancel = { task.cancel() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func suspendAndDrain() async {
        suspended = true; cancel?()
        if let active { await active() }
    }

    private func finishRetirement(_ handle: SharedMediaInboxHandle) async throws {
        let intent = try storage.inboxRetirement(handle)
        let proof = try await io.release(intent)
        do { try storage.inboxWrite(before: .beforeReleaseSave, after: .afterReleaseSave) { try $0.release(proof) } } catch {
            guard try !storage.inboxSources().contains(where: { $0.handle.id == handle.id }) else { throw error }
        }
    }

    private func reconcileOccupancy(_ source: SharedMediaInboxSource) async throws {
        let proof = try await io.occupancy(source)
        try storage.inboxWrite(before: .beforeOccupancySave, after: .afterOccupancySave) { try $0.reconcileOccupancy(proof) }
    }

    private func closeWriter(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxSource {
        if source.writerState == "closed" { return source }
        let proof = SharedMediaInboxWriterClosure(source: source, epoch: storage.inboxEpoch)
        return try transaction(before: .beforeCompletionSave, after: .afterCompletionSave) { try $0.closeWriter(proof) }
    }

    private func current(id: UUID, generation: UUID) throws -> SharedMediaInboxSource {
        guard let row = try storage.inboxSources().first(where: { $0.handle.id == id && $0.handle.generation == generation }) else {
            throw SharedMediaStorageFailure.stale
        }; return row
    }

    private func transaction(before: SharedMediaInboxBoundary, after: SharedMediaInboxBoundary,
                             _ body: (SharedMediaInboxLedger) throws -> SharedMediaInboxSource) throws -> SharedMediaInboxSource {
        var expected: SharedMediaInboxSource?
        do {
            return try storage.inboxWrite(before: before, after: after, requiresFreeSpace: before == .beforeReservationSave) { ledger in
                let result = try body(ledger); expected = result; return result
            }
        } catch {
            guard let expected, try current(id: expected.handle.id, generation: expected.handle.generation) == expected else { throw error }
            return expected
        }
    }
}

/// Minted only after this orchestrator's actual callback/I/O task has returned,
/// or while its exclusive reopened store/root lifetime excludes prior writers.
struct SharedMediaInboxWriterClosure: Sendable {
    let source: SharedMediaInboxSource
    let epoch: UUID
    fileprivate init(source: SharedMediaInboxSource, epoch: UUID) { self.source = source; self.epoch = epoch }
}

/// Created only after this coordinator has closed admission and awaited its
/// actual tracked task. It is never serialized or accepted by another lifetime.
struct SharedMediaPurgeDrain {
    let coordinatorID: UUID
    fileprivate init(coordinatorID: UUID) { self.coordinatorID = coordinatorID }
}
