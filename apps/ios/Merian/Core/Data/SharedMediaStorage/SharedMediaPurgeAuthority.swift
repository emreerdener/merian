import Foundation
import SwiftData

/// Receives a sealed transaction capability from the existing repository.
/// It owns no store, file actor, task or independent admission controller.
@MainActor
final class SharedMediaPurgeAuthority {
    private let transaction: SharedMediaPurgeTransaction
    #if DEBUG
    var fault: ((SharedMediaPurgeBoundary) throws -> Void)?
    #endif
    init(transaction: SharedMediaPurgeTransaction) { self.transaction = transaction }

    func begin(id: UUID) throws {
        let (context, row) = try transaction.read()
        guard transaction.coordinatorID != nil else { throw SharedMediaStorageFailure.closed }
        if row.phaseRaw != "readyP1" {
            guard try SharedMediaPurgeState.read(row).id == id else { throw SharedMediaStorageFailure.stale }
            return
        }
        try SharedMediaPurgeState(id: id, stage: .draining).install(row)
        try boundary(.beforeIntentSave); try transaction.save(context, row); try boundary(.afterIntentSave)
    }

    func access(id: UUID, drained: SharedMediaPurgeDrain) throws -> SharedMediaPurgeAccess {
        let (context, row) = try transaction.read()
        guard let coordinator = transaction.coordinatorID, drained.coordinatorID == coordinator,
              try SharedMediaPurgeState.read(row).id == id else { throw SharedMediaStorageFailure.stale }
        if try SharedMediaPurgeState.read(row).stage == .draining {
            try SharedMediaPurgeState(id: id, stage: .releasing).install(row)
            try boundary(.beforeDrainSave); try transaction.save(context, row); try boundary(.afterDrainSave)
        }
        return .init(id: id, generation: row.generation, binding: transaction.binding,
                     epoch: transaction.epoch, coordinatorID: coordinator)
    }

    func read<T>(_ access: SharedMediaPurgeAccess, _ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        let (context, row) = try checked(access)
        return try body(transaction.ledger(context, row))
    }

    func write<T>(_ access: SharedMediaPurgeAccess, before: SharedMediaPurgeBoundary,
                  after: SharedMediaPurgeBoundary, _ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        let (context, row) = try checked(access)
        guard try SharedMediaPurgeState.read(row).stage == .releasing else { throw SharedMediaStorageFailure.closed }
        let ledger = try transaction.ledger(context, row), result = try body(ledger)
        _ = try ledger.validate() // No fresh physical capacity or reservation.
        try boundary(before); try transaction.save(context, row); try boundary(after)
        return result
    }

    func isComplete(_ access: SharedMediaPurgeAccess) throws -> Bool {
        try SharedMediaPurgeState.read(checked(access).1).stage == .complete
    }

    func finish(_ access: SharedMediaPurgeAccess) throws -> SharedMediaPurgeCompletion {
        let (context, row) = try checked(access)
        try SharedMediaPurgeState.requireEmptyGraph(context)
        try transaction.verifyEmpty()
        if try SharedMediaPurgeState.read(row).stage != .complete {
            try SharedMediaPurgeState(id: access.id, stage: .complete).install(row)
            try boundary(.beforeTerminalSave); try transaction.save(context, row); try boundary(.afterTerminalSave)
        }
        return .init { [self] container in
            guard container === transaction.container else { throw SharedMediaStorageFailure.conflict }
            let (fresh, terminal) = try checked(access)
            guard try SharedMediaPurgeState.read(terminal).stage == .complete else { throw SharedMediaStorageFailure.closed }
            try SharedMediaPurgeState.requireEmptyGraph(fresh)
            try transaction.verifyEmpty()
        }
    }

    private func checked(_ access: SharedMediaPurgeAccess) throws -> (ModelContext, SharedMediaInventoryRecord) {
        let result = try transaction.read(), row = result.1
        let state = try SharedMediaPurgeState.read(row)
        guard access.id == state.id, access.generation == row.generation,
              access.binding == transaction.binding, access.epoch == transaction.epoch,
              access.coordinatorID == transaction.coordinatorID, state.stage != .draining else { throw SharedMediaStorageFailure.stale }
        return result
    }
    private func boundary(_ value: SharedMediaPurgeBoundary) throws {
        #if DEBUG
        try fault?(value)
        #endif
    }
}

struct SharedMediaPurgeAccess: Sendable {
    let id: UUID, generation: UUID, epoch: UUID, coordinatorID: UUID
    let binding: Data
    fileprivate init(id: UUID, generation: UUID, binding: Data, epoch: UUID, coordinatorID: UUID) {
        self.id = id; self.generation = generation; self.binding = binding
        self.epoch = epoch; self.coordinatorID = coordinatorID
    }
}

/// Ephemeral and non-forgeable outside the terminal verification owner. A
/// caller cannot convert a Boolean or a historical receipt into this authority.
@MainActor
struct SharedMediaPurgeCompletion {
    private let verify: (ModelContainer) throws -> Void
    fileprivate init(verify: @escaping (ModelContainer) throws -> Void) { self.verify = verify }
    func validate(in context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try verify(context.container)
        try SharedMediaPurgeState.requireEmptyGraph(context)
    }
}
