import Foundation
import SwiftData

/// Local-only coalesced recovery. No connectivity, account lease, provider work or retry timer.
@MainActor
final class ObservationReanalysisErasureOwner {
    private struct Request {
        let container: ModelContainer
        let isCurrent: @MainActor @Sendable () -> Bool
    }
    private let files: ObservationReanalysisFileStore
    private var suspensionCount = 0
    private var requested: Request?
    private var task: Task<Void, Never>?
    private var erasures: [UUID: Task<Void, Never>] = [:]
    private var inputErasures: [UUID: Task<Void, Never>] = [:]
    private var inputAdmission: (@MainActor (ModelContainer) throws -> SharedMediaNativeOriginalDrain.LocalBorrow)?
    private var inputAdmissionCurrent: (@MainActor () -> Bool)?
    private var inputClosed = false
    private var retired = false
    #if DEBUG
    /// Observation-only actual-exit seam; all live checks still run afterwards.
    var inputErasureCheckpoint: (@MainActor () async -> Void)?
    #endif

    init(files: ObservationReanalysisFileStore = .init(documents: .documentsDirectory)) { self.files = files }

    /// Terminally join every local cleanup task; durable receipts survive for
    /// a fresh owner. This is not a purge or renewed execution authority.
    func retire() async -> Bool {
        guard suspensionCount == 0 else { return false }
        retired = true; inputClosed = true; requested = nil
        let active = Array(erasures.values) + Array(inputErasures.values)
        task?.cancel()
        for work in active { work.cancel() }
        if let task { await task.value }
        for work in active { await work.value }
        return canCreateSuccessor
    }

    private var canCreateSuccessor: Bool {
        retired && suspensionCount == 0 && task == nil && erasures.isEmpty && inputErasures.isEmpty
    }

    func successor() throws -> ObservationReanalysisErasureOwner {
        guard canCreateSuccessor else { throw SharedMediaStorageFailure.closed }
        return ObservationReanalysisErasureOwner(files: files)
    }

    /// App supplies original startup/container authority, independently of a former account.
    func configureInputRecovery(admission: @escaping @MainActor (ModelContainer) throws -> SharedMediaNativeOriginalDrain.LocalBorrow,
                                isCurrent: @escaping @MainActor () -> Bool) throws {
        guard inputAdmission == nil, !inputClosed else { throw SharedMediaStorageFailure.closed }
        inputAdmission = admission; inputAdmissionCurrent = isCurrent
    }

    /// Called by the exact local registration. Never awaits the lifetime calling it.
    func closeInputRecovery() async -> Bool {
        inputClosed = true
        let active = Array(inputErasures.values)
        for task in active { task.cancel() }
        for task in active { await task.value }
        return inputErasures.isEmpty
    }

    func drain(container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async {
        guard !retired, suspensionCount == 0 else { return }
        requested = Request(container: container, isCurrent: isCurrent)
        if let task { await task.value; return }
        let active = Task {
            while let request = requested {
                requested = nil
                await pass(request)
            }
            task = nil
        }
        task = active
        await active.value
    }

    /// One exact receipt attempt, awaited by an existing retained task. Never joins the backlog loop.
    func erase(_ receipt: ObservationReanalysisErasureReceipt, container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool) async {
        guard !retired, suspensionCount == 0, isCurrent(), !Task.isCancelled else { return }
        if let existing = erasures[receipt.childID] { await existing.value; return }
        let active = Task { @MainActor [self] in
            defer { erasures[receipt.childID] = nil }
            await eraseReceipt(receipt, container: container, isCurrent: isCurrent)
        }
        erasures[receipt.childID] = active
        await active.value
    }

    private func eraseReceipt(_ receipt: ObservationReanalysisErasureReceipt, container: ModelContainer,
                              isCurrent: @escaping @MainActor @Sendable () -> Bool) async {
        let current: @MainActor @Sendable () -> Bool = { [self] in !retired && suspensionCount == 0 && isCurrent() }
        do {
            try await files.erase(child: receipt.childID, authorize: {
                try ObservationReanalysisErasurePersistence.validate(receipt, container: container, isCurrent: current)
            }, acknowledge: {
                _ = try ObservationReanalysisErasurePersistence.validate(receipt, container: container, isCurrent: current, complete: true)
            })
        } catch {
            // Busy, cancelled or failed cleanup retains its durable receipt for independent recovery.
            MerianLog.data.error("Reanalysis cleanup remains pending for a later local recovery opportunity.")
        }
    }

    /// Full-library erasure keeps local receipt work quiescent until its durable boundary completes.
    func suspendForLibraryPurge() async {
        suspensionCount += 1
        requested = nil
        let active = Array(erasures.values) + Array(inputErasures.values)
        task?.cancel()
        for work in active { work.cancel() }
        if let task { await task.value }
        for work in active { await work.value }
    }

    func resumeAfterLibraryPurge() { suspensionCount -= 1 }

    /// The fixed ledger references at most four inputs. No filename discovery or new bootstrap.
    private func recoverInputs(_ request: Request) async {
        guard suspensionCount == 0, !inputClosed, request.isCurrent(), !Task.isCancelled,
              inputAdmissionCurrent?() == true, let inputAdmission else { return }
        do {
            // A bounded existence read is only a scheduling hint, never erasure authority.
            guard try ObservationReanalysisInputPersistence.hasOwnership(context: ModelContext(request.container)) else { return }
            let borrow = try inputAdmission(request.container)
            _ = try borrow.fence(container: request.container)
            let state = try ObservationReanalysisInputPersistence.inspect(container: request.container)
            for receipt in state.receipts.compactMap({ $0 }) where receipt.phase != .complete {
                await eraseInput(receipt, container: request.container, borrowing: borrow, isCurrent: request.isCurrent)
            }
        } catch {
            // Missing or damaged control is a hold, never reconstruction authority.
            MerianLog.data.error("Private input recovery remains held for a later local opportunity.")
        }
    }

    /// Direct and backlog callers share actual-exit accounting for the same child.
    func eraseInput(_ receipt: ObservationReanalysisInputReceipt, container: ModelContainer,
                    borrowing: SharedMediaNativeOriginalDrain.LocalBorrow,
                    isCurrent: @escaping @MainActor @Sendable () -> Bool) async {
        guard suspensionCount == 0, !inputClosed, isCurrent(), !Task.isCancelled,
              inputAdmissionCurrent?() == true else { return }
        if let existing = inputErasures[receipt.childID] { await existing.value; return }
        guard inputErasures.count < ObservationReanalysisInputReceipt.maximumReservations else { return }
        let active = Task { @MainActor [self] in
            defer { inputErasures[receipt.childID] = nil }
            do {
                let fence = try borrowing.fence(container: container)
                let validate: @MainActor @Sendable () throws -> Void = { [self] in
                    try Task.checkCancellation()
                    guard suspensionCount == 0, !inputClosed, isCurrent(), inputAdmissionCurrent?() == true else {
                        throw SharedMediaStorageFailure.closed
                    }
                    try borrowing.require(container: container, fence: fence)
                }
                try validate()
                #if DEBUG
                if TestExecutionCoordinator.isRunningUnitTests { await inputErasureCheckpoint?() }
                #endif
                try validate()
                try await files.eraseInput(child: receipt.childID, read: {
                    try validate()
                    guard let current = try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: container),
                          current.hasSameReservation(as: receipt) else { throw ObservationHistoryError.resultConflict }
                    return current
                }, advance: {
                    try ObservationReanalysisInputPersistence.advance(from: $0, to: $1, container: container, validate: validate)
                })
            } catch {
                MerianLog.data.error("Private input cleanup remains pending with its exact receipt.")
            }
        }
        inputErasures[receipt.childID] = active
        await active.value
    }

    private func pass(_ request: Request) async {
        await recoverInputs(request)
        var afterID = ""
        while !retired && request.isCurrent() && !Task.isCancelled {
            let jobs: [(String, ObservationReanalysisErasureReceipt?)]
            do {
                let context = ModelContext(request.container)
                let kind = OfflineJobKind.observationReanalysisErasure.rawValue, pending = OfflineJobStatus.pending.rawValue
                let cursor = afterID
                var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
                    $0.kindRaw == kind && $0.statusRaw == pending && $0.id > cursor
                }, sortBy: [SortDescriptor(\.id)])
                query.fetchLimit = 64
                jobs = try context.fetch(query).map { ($0.id, try? ObservationReanalysisErasureReceipt.restore($0)) }
            } catch {
                MerianLog.data.error("Reanalysis cleanup discovery failed; retaining local receipts.")
                return
            }
            guard !jobs.isEmpty else { return }
            for (id, receipt) in jobs {
                afterID = id
                guard request.isCurrent(), !Task.isCancelled else { return }
                guard let receipt else { continue }
                await erase(receipt, container: request.container, isCurrent: request.isCurrent)
            }
            await Task.yield()
        }
    }
}
