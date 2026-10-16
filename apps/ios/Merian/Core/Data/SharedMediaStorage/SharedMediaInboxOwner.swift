import Foundation
import SwiftData

/// Explicit isolated composition only. Source operations are device-local and
/// accountless. The single task retains every fence through cancellation drain.
@MainActor
final class SharedMediaInboxOwner {
    private let storage: SharedMediaStorageRepository
    private let io: SharedMediaInboxIO
    private var active: (() async -> Void)?
    private var cancel: (() -> Void)?
    private var suspended = false

    init(container: ModelContainer, authorityRoot: URL, inboxRoot: URL, photoRoot: URL, inventoryID: UUID) throws {
        storage = try SharedMediaStorageRepository(container: container, authorityRoot: authorityRoot,
            inventoryID: inventoryID, mode: .p1InboxQualification,
            sources: [SharedMediaInboxFiles.namespace: inboxRoot, SharedMediaPhotoLedger.namespace: photoRoot])
        guard let files = storage.inboxFiles else { throw SharedMediaStorageFailure.closed }
        io = SharedMediaInboxIO(files: files)
    }

    #if DEBUG
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

    func suspendAndDrain() async {
        suspended = true; cancel?()
        if let active { await active() }
    }

    private func finishRetirement(_ handle: SharedMediaInboxHandle) async throws {
        let intent = try storage.inboxRetirement(handle)
        let proof = try await io.release(intent)
        do { try storage.inboxWrite(before: .beforeReleaseSave, after: .afterReleaseSave) { try $0.release(proof) } }
        catch {
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

private actor SharedMediaInboxIO {
    let files: SharedMediaInboxFiles
    init(files: SharedMediaInboxFiles) { self.files = files }
    func load(_ callback: @Sendable () async throws -> Data) async throws -> Data { try await callback() }
    func prepare(_ data: Data, maximum: Int64) throws -> SharedMediaInboxPrepared { try SharedMediaInboxFiles.prepare(data, maximumBytes: maximum) }
    func validate(_ sources: [SharedMediaInboxSource]) throws { try files.validateInventory(sources) }
    func occupancy(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxOccupancyProof { try files.occupancy(source) }
    func begin(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxFileIdentity { try files.begin(source) }
    func write(_ data: Data, source: SharedMediaInboxSource) throws -> SharedMediaInboxCompletionProof { try files.write(data, source: source) }
    func recover(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxCompletionProof? { try files.recover(source) }
    func read(_ source: SharedMediaInboxSource) throws -> Data { try files.read(source) }
    func inspectRetirement(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxRetirementInspection { try files.inspectRetirement(source) }
    func release(_ intent: SharedMediaInboxRetirement) throws -> SharedMediaInboxReleaseProof { try files.release(intent) }
    #if DEBUG
    func setFault(_ fault: (@Sendable (SharedMediaInboxBoundary) throws -> Void)?) { files.fault = fault }
    #endif
}
