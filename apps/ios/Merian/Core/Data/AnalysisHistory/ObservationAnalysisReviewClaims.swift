import Foundation
import SwiftData

extension ObservationAnalysisReviewPersistence {
    struct Claim: Sendable {
        let intent: ObservationAnalysisReviewIntent
        let attempt: Int
        let startedAt: Date
        let expiresAt: Date
    }

    @MainActor
    static func candidates(container: ModelContainer, ownerID: UUID) throws -> [(ObservationAnalysisReviewIntent, Date)] {
        let context = ModelContext(container)
        let kind = OfflineJobKind.observationAnalysisReviewSync.rawValue
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.kindRaw == kind },
            sortBy: [SortDescriptor(\.createdAt)]))
        return jobs.compactMap { job in
            guard [.pending, .waiting, .running].contains(job.status), job.attemptCount >= 0, job.attemptCount < Int.max,
                  let intent = try? restore(job), !intent.isComplete, intent.ownerID == ownerID,
                  let scan = try? ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: context),
                  scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
                  (try? ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) == false else { return nil }
            guard (try? transaction(intent, container: container, isCurrent: { true }, body: { _ in true })) == true else { return nil }
            return (intent, job.nextRunAt ?? job.createdAt)
        }
    }

    @MainActor
    static func claim(_ expected: ObservationAnalysisReviewIntent, at date: Date, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim? {
        try transaction(expected, container: container, isCurrent: isCurrent, save: save) { context in
            guard let job = try context.fetchOfflineJob(id: jobID(expected.request.operationID, observationID: expected.request.observationID)),
                  try restore(job).storedData() == expected.storedData() else { throw IntegrityError.conflict }
            guard !expected.isComplete, [.pending, .waiting, .running].contains(job.status),
                  job.nextRunAt.map({ $0 <= date }) ?? true else { return nil }
            guard ObservationAnalysisReviewIntent.validDate(date), job.attemptCount >= 0, job.attemptCount < Int.max else { throw IntegrityError.conflict }
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
            guard !claim.intent.hasReceipt, ObservationAnalysisReviewIntent.validDate(date), date >= claim.startedAt, date < claim.expiresAt,
                  let job = try context.fetchOfflineJob(id: jobID(claim.intent.request.operationID, observationID: claim.intent.request.observationID)) else {
                throw IntegrityError.unavailable
            }
            try validate(claim, job: job)
        }
    }

    static func validate(_ claim: Claim, job: OfflineJobRecord) throws {
        guard job.statusRaw == OfflineJobStatus.running.rawValue, job.attemptCount == claim.attempt,
              job.lastAttemptAt == claim.startedAt, job.nextRunAt == claim.expiresAt,
              try restore(job).storedData() == claim.intent.storedData() else { throw IntegrityError.conflict }
    }

    @MainActor
    static func retry(_ claim: Claim, at date: Date, needsAttention: Bool, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try transaction(claim.intent, container: container, isCurrent: isCurrent, save: save) { context in
            guard let job = try context.fetchOfflineJob(id: jobID(claim.intent.request.operationID, observationID: claim.intent.request.observationID)) else {
                throw IntegrityError.unavailable
            }
            try validate(claim, job: job)
            guard ObservationAnalysisReviewIntent.validDate(date) else { throw IntegrityError.conflict }
            job.status = needsAttention ? .needsAttention : .waiting
            job.nextRunAt = needsAttention ? nil : date.addingTimeInterval(min(300, pow(2, Double(min(claim.attempt, 7) + 1))))
            job.lastErrorCode = needsAttention ? "analysis_review_requires_attention" : "analysis_review_reconcile"
            job.updatedAt = date
        }
    }
}
