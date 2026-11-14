import Foundation
import SwiftData

/// Local input accounting inside the existing erasure job storage. The caller
/// retains filesystem/store fences; no transaction or model survives an await.
enum ObservationReanalysisInputPersistence {
    typealias Receipt = ObservationReanalysisInputReceipt
    typealias Ledger = ObservationReanalysisInputLedger
    typealias Save = (ModelContext) throws -> Void
    struct Snapshot: Sendable {
        let ledger: Ledger
        let receipts: [Receipt?]
    }

    /// Explicit fresh preparation and exclusively locked physical initialization
    /// supply authority. Missing metadata alone never calls this entry point.
    @MainActor
    static func initialize(_ ledger: Ledger, container: ModelContainer,
                           validate: (ModelContext) throws -> Void,
                           save: Save = { try $0.save() }) throws {
        try ledger.validate()
        guard ledger.slots.allSatisfy({ $0.state == .initial }) else { throw MerianError.invalidResponse }
        try transaction(container: container) { context in
            try validate(context)
            let lower = Ledger.ownershipLowerBound, upper = Ledger.ownershipUpperBound, controlID = Ledger.jobID
            var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
                $0.id >= lower && $0.id < upper && $0.id != controlID
            })
            query.fetchLimit = 1
            guard try context.fetch(query).isEmpty else { throw ObservationHistoryError.resultConflict }
            if let existing = try context.fetchOfflineJob(id: Ledger.jobID) {
                guard try restoreLedger(existing) == ledger else { throw ObservationHistoryError.resultConflict }
                return
            }
            context.insert(OfflineJobRecord(id: Ledger.jobID, kind: .observationReanalysisErasure,
                subjectId: ledger.namespaceGeneration.uuidString.lowercased(), allowsCellular: false, metadataJSON: try ledger.encoded()))
            try Task.checkCancellation(); try validate(context)
            try save(context)
        }
    }

    @MainActor
    static func inspect(container: ModelContainer) throws -> Snapshot {
        try transaction(container: container) { try snapshot(context: $0) }
    }

    /// Explicit fresh-preparation bootstrap only. Existing authority is fully
    /// validated; a missing control plus any surviving input row is a hold.
    /// The caller still proves physical absence under exclusive Documents lock.
    @MainActor
    static func inspectForFreshPreparation(container: ModelContainer) throws -> Snapshot? {
        try transaction(container: container) { context in
            if try context.fetchOfflineJob(id: Ledger.jobID) != nil { return try snapshot(context: context) }
            let lower = Ledger.ownershipLowerBound, upper = Ledger.ownershipUpperBound
            var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id >= lower && $0.id < upper })
            query.fetchLimit = 1
            guard try context.fetch(query).isEmpty else { throw ObservationHistoryError.resultConflict }
            return nil
        }
    }

    @MainActor
    static func hasOwnership(context: ModelContext) throws -> Bool {
        let lower = Ledger.ownershipLowerBound, upper = Ledger.ownershipUpperBound
        var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id >= lower && $0.id < upper })
        query.fetchLimit = 1
        return try !context.fetch(query).isEmpty
    }

    /// Only the validated control is bookkeeping when all slots are quiescent.
    /// Child jobs keep their ordinary status accounting; malformed links throw.
    @MainActor
    static func hasQuiescentControl(context: ModelContext) throws -> Bool {
        guard try hasOwnership(context: context) else { return false }
        let state = try snapshot(context: context)
        return state.ledger.slots.allSatisfy { $0.state != .active }
    }

    /// Completed exact replay does not inspect or modify a possibly reused slot.
    /// Active receipts must still belong to the current, freshly validated graph.
    @MainActor
    static func read(child: UUID, container: ModelContainer) throws -> Receipt? {
        try transaction(container: container) { context in
            guard let row = try context.fetchOfflineJob(id: Receipt.prefix + child.uuidString.lowercased()) else { return nil }
            let receipt = try restore(row)
            if receipt.phase != .complete {
                let state = try snapshot(context: context)
                try state.ledger.validate(receipt, for: state.ledger.slots[receipt.slot])
            }
            return receipt
        }
    }

    /// The namespace admission lock and the selected stable slot lock precede
    /// this call. Exact replay happens before any charge or successor allocation.
    @MainActor
    static func reserve(_ requested: Receipt, container: ModelContainer,
                        validate: (ModelContext) throws -> Void,
                        save: Save = { try $0.save() }) throws -> Receipt {
        try requested.validate()
        guard requested.phase == .reserved else { throw MerianError.invalidResponse }
        return try transaction(container: container) { context in
            try validate(context)
            if let row = try context.fetchOfflineJob(id: requested.jobID) {
                let existing = try restore(row)
                guard existing.hasSameReservation(as: requested) else { throw ObservationHistoryError.resultConflict }
                if existing.phase != .complete {
                    let state = try snapshot(context: context)
                    try state.ledger.validate(existing, for: state.ledger.slots[existing.slot])
                }
                return existing
            }
            let state = try snapshot(context: context)
            let next = try state.ledger.reserving(requested, prior: state.receipts[requested.slot])
            guard let control = try context.fetchOfflineJob(id: Ledger.jobID) else { throw ObservationHistoryError.unavailable }
            context.insert(OfflineJobRecord(id: requested.jobID, kind: .observationReanalysisErasure,
                subjectId: requested.childID.uuidString.lowercased(), allowsCellular: false,
                approximateBytes: Int64(ScanMediaPayloadPolicy.maxSavedVideoBytes), metadataJSON: try requested.encoded()))
            control.metadataJSON = try next.encoded()
            try Task.checkCancellation(); try validate(context)
            try save(context)
            return requested
        }
    }

    /// File identity is committed before bytes; erasing is committed before
    /// unlink. Completion atomically releases only this exact slot generation.
    @MainActor
    static func advance(from expected: Receipt, to next: Receipt, container: ModelContainer,
                        validate: () throws -> Void, save: Save = { try $0.save() }) throws -> Receipt {
        try validateTransition(from: expected, to: next)
        return try transaction(container: container) { context in
            try validate()
            guard let row = try context.fetchOfflineJob(id: expected.jobID) else { throw ObservationHistoryError.unavailable }
            let current = try restore(row)
            if current == next, next.phase == .complete { return current }
            let state = try snapshot(context: context)
            try state.ledger.validate(current, for: state.ledger.slots[current.slot])
            if current == next { return current }
            guard current == expected else { throw ObservationHistoryError.resultConflict }
            row.metadataJSON = try next.encoded()
            row.status = next.phase == .complete ? .complete : .pending
            if next.phase == .complete {
                let ledger = try state.ledger.releasing(expected, completed: next)
                guard let control = try context.fetchOfflineJob(id: Ledger.jobID) else { throw ObservationHistoryError.unavailable }
                control.metadataJSON = try ledger.encoded()
            }
            try Task.checkCancellation(); try validate()
            try save(context)
            // Throwing/uncertain saves are reconciled through exact original and
            // next records. The caller cannot release a second generation.
            return next
        }
    }

    @MainActor
    static func restore(_ row: OfflineJobRecord) throws -> Receipt {
        try validateJob(row, bytes: Int64(ScanMediaPayloadPolicy.maxSavedVideoBytes))
        guard let text = row.metadataJSON else { throw MerianError.invalidResponse }
        let receipt = try Receipt.decode(text)
        guard row.id == receipt.jobID, row.subjectId == receipt.childID.uuidString.lowercased(),
              row.statusRaw == (receipt.phase == .complete ? OfflineJobStatus.complete.rawValue : OfflineJobStatus.pending.rawValue) else {
            throw MerianError.invalidResponse
        }
        return receipt
    }

    @MainActor
    private static func restoreLedger(_ row: OfflineJobRecord) throws -> Ledger {
        try validateJob(row, bytes: 0)
        guard row.id == Ledger.jobID, row.statusRaw == OfflineJobStatus.pending.rawValue,
              let text = row.metadataJSON else { throw MerianError.invalidResponse }
        let ledger = try Ledger.decode(text)
        guard row.subjectId == ledger.namespaceGeneration.uuidString.lowercased() else { throw MerianError.invalidResponse }
        return ledger
    }

    @MainActor
    private static func snapshot(context: ModelContext) throws -> Snapshot {
        guard let control = try context.fetchOfflineJob(id: Ledger.jobID) else { throw ObservationHistoryError.unavailable }
        let ledger = try restoreLedger(control)
        var receipts: [Receipt?] = []
        for slot in ledger.slots {
            if slot.state == .initial { receipts.append(nil); continue }
            guard let child = slot.childID,
                  let row = try context.fetchOfflineJob(id: Receipt.prefix + child.uuidString.lowercased()) else {
                throw ObservationHistoryError.resultConflict
            }
            let receipt = try restore(row)
            try ledger.validate(receipt, for: slot)
            receipts.append(receipt)
        }
        return Snapshot(ledger: ledger, receipts: receipts)
    }

    @MainActor
    private static func validateJob(_ row: OfflineJobRecord, bytes: Int64) throws {
        guard row.kindRaw == OfflineJobKind.observationReanalysisErasure.rawValue,
              row.priority == 0, row.attemptCount == 0, row.nextRunAt == nil, row.lastAttemptAt == nil,
              row.lastErrorCode == nil, row.lastErrorMessage == nil, row.lastHTTPStatus == nil,
              row.serverStatus == nil, row.serverStage == nil, row.serverRetryAfter == nil,
              !row.requiresUnconstrainedNetwork, !row.allowsCellular,
              row.approximateBytes == bytes else { throw MerianError.invalidResponse }
    }

    @MainActor
    private static func transaction<Value>(container: ModelContainer, body: (ModelContext) throws -> Value) throws -> Value {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try Task.checkCancellation()
            guard !container.mainContext.hasChanges else { throw ObservationHistoryError.unavailable }
            let context = ModelContext(container); context.autosaveEnabled = false
            do { return try body(context) } catch { context.rollback(); throw error }
        }
    }

    private static func validateTransition(from expected: Receipt, to next: Receipt) throws {
        try expected.validate(); try next.validate()
        guard expected.hasSameReservation(as: next) else { throw ObservationHistoryError.resultConflict }
        let allowed: Receipt
        switch (expected.phase, next.phase) {
        case (.reserved, .fileBound):
            guard let identity = next.file else { throw MerianError.invalidResponse }
            allowed = try expected.binding(file: identity)
        case (.fileBound, .copied):
            guard let snapshot = next.snapshot else { throw MerianError.invalidResponse }
            allowed = try expected.copied(snapshot: snapshot)
        case (.reserved, .erasing), (.fileBound, .erasing), (.copied, .erasing):
            allowed = try expected.retiring()
        case (.erasing, .complete):
            allowed = try expected.completed()
        default:
            throw MerianError.invalidResponse
        }
        guard allowed == next else { throw ObservationHistoryError.resultConflict }
    }
}
