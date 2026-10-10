import Foundation
import SwiftData

extension ProtectedInsightChatPersistence {
    static let claimLifetime: TimeInterval = 180
    static let heldCode = "protected_chat_reconcile"

    struct Claim: Sendable {
        let intent: ProtectedInsightChatIntent
        let attempt: Int
        let startedAt: Date
        var expiresAt: Date { startedAt.addingTimeInterval(claimLifetime) }
        fileprivate init(intent: ProtectedInsightChatIntent, attempt: Int, startedAt: Date) {
            self.intent = intent; self.attempt = attempt; self.startedAt = startedAt
        }
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (0...32_503_680_000).contains(date.timeIntervalSince1970)
    }

    /// Closed persisted states. A deadline on held work or a damaged running row is never runnable.
    static func validateShape(_ job: OfflineJobRecord, intent: ProtectedInsightChatIntent) throws {
        guard job.attemptCount >= 0, job.attemptCount < Int.max,
              job.lastAttemptAt.map(validDate) ?? true, job.nextRunAt.map(validDate) ?? true else { throw IntegrityError.conflict }
        let untouched = job.attemptCount == 0 && job.lastAttemptAt == nil
        let attempted = job.attemptCount > 0 && job.lastAttemptAt != nil
        switch job.statusRaw {
        case OfflineJobStatus.pending.rawValue:
            guard !intent.isComplete, untouched, job.nextRunAt == nil, job.lastErrorCode == nil else { throw IntegrityError.conflict }
        case OfflineJobStatus.running.rawValue:
            guard !intent.isComplete, attempted, let start = job.lastAttemptAt, let expiry = job.nextRunAt,
                  abs(expiry.timeIntervalSince(start) - claimLifetime) < 0.001, job.lastErrorCode == nil else { throw IntegrityError.conflict }
        case OfflineJobStatus.needsAttention.rawValue:
            guard !intent.isComplete, attempted, job.nextRunAt == nil, job.lastErrorCode == heldCode else { throw IntegrityError.conflict }
        case OfflineJobStatus.complete.rawValue:
            // Version-one prepared receipts can have no execution provenance; they remain terminal.
            guard intent.isComplete, untouched || attempted, job.nextRunAt == nil, job.lastErrorCode == nil else { throw IntegrityError.conflict }
        default: throw IntegrityError.conflict
        }
    }

    @MainActor
    static func claimInitial(_ intent: ProtectedInsightChatIntent, at date: Date, container: ModelContainer,
                             isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim? {
        try mutate(intent, container: container, isCurrent: isCurrent, save: save) { job, saved in
            try Task.checkCancellation()
            guard !saved.isComplete, job.status == .pending else { return nil }
            guard try saved.storedData() == intent.storedData() else { throw IntegrityError.conflict }
            return try begin(saved, job: job, at: date)
        }
    }

    /// Restart/status recovery only. Returning the prior attempt never authorizes a send or wakes work.
    @MainActor
    static func currentAttempt(_ intent: ProtectedInsightChatIntent, container: ModelContainer, isCurrent: () -> Bool) throws -> Claim? {
        try mutate(intent, container: container, isCurrent: isCurrent) { job, saved in
            guard !saved.isComplete, [.running, .needsAttention].contains(job.status), let start = job.lastAttemptAt else { return nil }
            return Claim(intent: saved, attempt: job.attemptCount, startedAt: start)
        }
    }

    /// Only an explicit user action may call this. A stale tap cannot claim a newer held attempt.
    @MainActor
    static func claimExplicitReplay(_ previous: Claim, at date: Date, container: ModelContainer,
                                    isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim? {
        try mutate(previous.intent, container: container, isCurrent: isCurrent, save: save) { job, saved in
            try Task.checkCancellation()
            guard !saved.isComplete else { return nil }
            try validate(previous, job: job, saved: saved, permitsHeld: true)
            guard validDate(date), date >= previous.startedAt else { throw IntegrityError.conflict }
            guard job.status == .needsAttention || date >= previous.expiresAt else { return nil }
            return try begin(saved, job: job, at: date)
        }
    }

    private static func begin(_ intent: ProtectedInsightChatIntent, job: OfflineJobRecord, at date: Date) throws -> Claim {
        guard validDate(date), validDate(date.addingTimeInterval(claimLifetime)),
              job.attemptCount < Int.max - 1 else { throw IntegrityError.conflict }
        job.attemptCount += 1; job.status = .running; job.lastAttemptAt = date
        job.nextRunAt = date.addingTimeInterval(claimLifetime); job.lastErrorCode = nil; job.updatedAt = date
        return Claim(intent: intent, attempt: job.attemptCount, startedAt: date)
    }

    @MainActor
    static func requireDispatch(_ claim: Claim, at date: Date, container: ModelContainer, isCurrent: () -> Bool) throws {
        try mutate(claim.intent, container: container, isCurrent: isCurrent) { job, saved in
            try Task.checkCancellation()
            guard validDate(date), date >= claim.startedAt, date < claim.expiresAt else { throw IntegrityError.unavailable }
            try validate(claim, job: job, saved: saved)
        }
    }

    /// Exact local recovery only. This never grants permission to call the HTTP send endpoint.
    @MainActor
    static func read(_ intent: ProtectedInsightChatIntent, container: ModelContainer,
                     isCurrent: () -> Bool) throws -> ProtectedInsightChatIntent {
        try mutate(intent, container: container, isCurrent: isCurrent) { _, saved in saved }
    }

    /// A known answer survives cancellation/expiry, but never a replaced claim or account scope.
    @MainActor
    static func requireResponse(_ claim: Claim, container: ModelContainer, isCurrent: () -> Bool) throws {
        try mutate(claim.intent, container: container, isCurrent: isCurrent) { job, saved in
            try validate(claim, job: job, saved: saved)
        }
    }

    /// Holds have no wake deadline. Cancellation settlement still checks owner and exact durable claim.
    @MainActor
    static func hold(_ claim: Claim, at date: Date, container: ModelContainer,
                     isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try mutate(claim.intent, container: container, isCurrent: isCurrent, save: save) { job, saved in
            try validate(claim, job: job, saved: saved, permitsHeld: true)
            guard validDate(date), date >= claim.startedAt else { throw IntegrityError.conflict }
            if job.status == .needsAttention { return }
            job.status = .needsAttention; job.nextRunAt = nil; job.lastErrorCode = heldCode; job.updatedAt = date
        }
    }

    /// A committed exact answer may arrive after expiry. A replaced or held claim cannot overwrite it.
    @MainActor
    static func acknowledge(_ data: Data, claim: Claim, at date: Date, container: ModelContainer,
                            isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ProtectedInsightChatIntent {
        try mutate(claim.intent, container: container, isCurrent: isCurrent, save: save) { job, saved in
            guard job.attemptCount == claim.attempt, job.lastAttemptAt == claim.startedAt,
                  validDate(date), date >= claim.startedAt else { throw IntegrityError.conflict }
            if saved.isComplete { return try saved.accepting(data, at: date) }
            try validate(claim, job: job, saved: saved)
            let complete = try saved.accepting(data, at: date)
            guard let metadata = String(bytes: try complete.storedData(), encoding: .utf8) else { throw IntegrityError.conflict }
            job.metadataJSON = metadata; job.status = .complete; job.nextRunAt = nil; job.lastErrorCode = nil; job.updatedAt = date
            return complete
        }
    }

    private static func validate(_ claim: Claim, job: OfflineJobRecord, saved: ProtectedInsightChatIntent, permitsHeld: Bool = false) throws {
        guard job.attemptCount == claim.attempt, job.lastAttemptAt == claim.startedAt,
              try saved.storedData() == claim.intent.storedData(),
              (job.status == .running && job.nextRunAt == claim.expiresAt)
                || (permitsHeld && job.status == .needsAttention && job.nextRunAt == nil) else { throw IntegrityError.conflict }
    }

    @MainActor
    private static func mutate<T>(_ expected: ProtectedInsightChatIntent, container: ModelContainer, isCurrent: () -> Bool,
                                  save: (ModelContext) throws -> Void = { try $0.save() },
                                  body: (OfflineJobRecord, ProtectedInsightChatIntent) throws -> T) throws -> T {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                _ = try requireScope(expected, context: context)
                let id = jobID(expected.request)
                let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == id }))
                guard jobs.count == 1, let job = jobs.first else { throw IntegrityError.unavailable }
                let saved = try restore(job)
                guard saved.ownerID == expected.ownerID, saved.request == expected.request,
                      saved.requestSHA256 == expected.requestSHA256 else { throw IntegrityError.conflict }
                let result = try body(job, saved)
                guard isCurrent() else { throw IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return result
            } catch { context.rollback(); throw error }
        }
    }
}
