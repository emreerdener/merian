import Foundation
import SwiftData

extension ObservationPublicationPersistence {
    struct Claim: Sendable {
        let intent: ObservationPublicationIntent
        let attempt: Int
        let startedAt: Date
        let expiresAt: Date
    }

    @MainActor
    static func candidates(container: ModelContainer, ownerID: UUID) throws -> [(ObservationPublicationIntent, Date)] {
        let context = ModelContext(container)
        let kind = OfflineJobKind.observationPublicationSync.rawValue
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.kindRaw == kind },
            sortBy: [SortDescriptor(\.createdAt)]))
        return try discover(jobs, ownerID: ownerID) { intent in
            try transaction(intent, container: container, isCurrent: { true }, body: { _ in })
        }
    }

    /// Skip corrupt rows, but propagate storage failures to the bounded retry owner.
    @MainActor
    static func discover(_ jobs: [OfflineJobRecord], ownerID: UUID,
                         validateScope: (ObservationPublicationIntent) throws -> Void) throws -> [(ObservationPublicationIntent, Date)] {
        try jobs.compactMap { job in
            guard let intent = try? restore(job), intent.ownerID == ownerID,
                  (try? runnableShape(job, intent: intent)) == true else { return nil }
            do {
                try validateScope(intent)
            } catch ObservationHistoryError.deleted { return nil
            } catch ObservationHistoryError.unavailable { return nil
            } catch IntegrityError.unavailable { return nil
            } catch IntegrityError.conflict { return nil }
            return (intent, job.nextRunAt ?? job.createdAt)
        }
    }

    /// The same structural proof protects discovery, direct claim and local status.
    static func validatedStatus(_ job: OfflineJobRecord, intent: ObservationPublicationIntent) throws -> OfflineJobStatus {
        guard let status = OfflineJobStatus(rawValue: job.statusRaw),
              job.attemptCount >= 0, job.attemptCount < Int.max,
              validDate(job.createdAt), validDate(job.updatedAt),
              job.nextRunAt.map(validDate) ?? true, job.lastAttemptAt.map(validDate) ?? true,
              (job.attemptCount == 0) == (job.lastAttemptAt == nil) else { throw IntegrityError.conflict }
        if intent.isTerminal {
            guard status == .complete, job.nextRunAt == nil else { throw IntegrityError.conflict }
            return status
        }
        switch status {
        case .pending:
            guard intent.receipt == nil, job.attemptCount == 0, job.nextRunAt == nil else { throw IntegrityError.conflict }
        case .running:
            guard job.attemptCount > 0, let start = job.lastAttemptAt, let expiry = job.nextRunAt,
                  abs(expiry.timeIntervalSince(start) - 180) < 0.001 else { throw IntegrityError.conflict }
        case .waiting:
            // Acknowledgement without a dispatch claim legitimately leaves attempt zero.
            guard job.nextRunAt != nil, intent.receipt != nil || job.attemptCount > 0 else { throw IntegrityError.conflict }
        case .needsAttention:
            guard job.attemptCount > 0, job.nextRunAt == nil else { throw IntegrityError.conflict }
        case .complete, .cancelled: throw IntegrityError.conflict
        }
        return status
    }

    static func runnableShape(_ job: OfflineJobRecord, intent: ObservationPublicationIntent) throws -> Bool {
        let status = try validatedStatus(job, intent: intent)
        return [.pending, .running, .waiting].contains(status) && job.attemptCount < Int.max - 1
    }

    static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (0...32_503_680_000).contains(date.timeIntervalSince1970)
    }

    @MainActor
    static func claim(_ expected: ObservationPublicationIntent, at date: Date, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim? {
        try transaction(expected, container: container, isCurrent: isCurrent, save: save) { context in
            guard let job = try context.fetchOfflineJob(id: jobID(expected.identity.operationID, observationID: expected.identity.observationID)),
                  try restore(job).storedData() == expected.storedData() else { throw IntegrityError.conflict }
            guard try runnableShape(job, intent: expected),
                  job.nextRunAt.map({ $0 <= date }) ?? true else { return nil }
            guard validDate(date), validDate(date.addingTimeInterval(180)) else { throw IntegrityError.conflict }
            job.attemptCount += 1
            job.status = .running; job.lastAttemptAt = date; job.updatedAt = date
            let expiry = date.addingTimeInterval(180)
            job.nextRunAt = expiry
            return Claim(intent: expected, attempt: job.attemptCount, startedAt: date, expiresAt: expiry)
        }
    }

    /// A late completion may settle its unchanged claim; only new dispatch requires unexpired work.
    @MainActor
    static func requireDispatch(_ claim: Claim, at date: Date, container: ModelContainer, isCurrent: () -> Bool) throws {
        try transaction(claim.intent, container: container, isCurrent: isCurrent) { context in
            guard validDate(date), date >= claim.startedAt, date < claim.expiresAt,
                  let job = try context.fetchOfflineJob(id: jobID(claim.intent.identity.operationID, observationID: claim.intent.identity.observationID)) else {
                throw IntegrityError.unavailable
            }
            try validate(claim, job: job)
        }
    }

    static func validate(_ claim: Claim, job: OfflineJobRecord) throws {
        guard try validatedStatus(job, intent: claim.intent) == .running, job.attemptCount == claim.attempt,
              job.lastAttemptAt == claim.startedAt, job.nextRunAt == claim.expiresAt,
              try restore(job).storedData() == claim.intent.storedData() else { throw IntegrityError.conflict }
    }

    @MainActor
    static func retry(_ claim: Claim, at date: Date, needsAttention: Bool, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try transaction(claim.intent, container: container, isCurrent: isCurrent, save: save) { context in
            guard let job = try context.fetchOfflineJob(id: jobID(claim.intent.identity.operationID, observationID: claim.intent.identity.observationID)) else {
                throw IntegrityError.unavailable
            }
            try validate(claim, job: job)
            guard validDate(date), validDate(date.addingTimeInterval(300)) else { throw IntegrityError.conflict }
            job.status = needsAttention ? .needsAttention : .waiting
            job.nextRunAt = needsAttention ? nil : date.addingTimeInterval(min(300, pow(2, Double(min(claim.attempt, 7) + 1))))
            job.lastErrorCode = needsAttention ? "publication_requires_attention" : "publication_reconcile"
            job.updatedAt = date
        }
    }
}
