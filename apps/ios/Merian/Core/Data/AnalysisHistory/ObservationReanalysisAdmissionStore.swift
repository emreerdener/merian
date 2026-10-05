import Foundation
import SwiftData

/// Exact-byte CAS for unbound submission recovery. Normal execution fields remain pristine.
@MainActor
enum ObservationReanalysisAdmissionStore {
    typealias Work = ObservationReanalysisAdmissionWork
    private typealias Persistence = ObservationReanalysisPersistence
    enum Admission { case initial, dueRetry, interrupted }
    enum Settlement { case waiting(Date), held(Work.Hold) }
    struct Snapshot: Equatable, Sendable {
        let work: Work
        let metadata: String
        var identity: OfflineQueueWork.Reanalysis { work.preparation.draft.identity }
    }
    struct Claim: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }
    struct Pair {
        let row: OfflineQueuedScan
        let job: OfflineJobRecord
        let snapshot: Snapshot
    }
    struct Candidate {
        let snapshot: Snapshot
        let admission: Admission
        let due: Date
    }

    static func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                     isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try pair(identity, context: context).snapshot
        }
    }

    static func candidates(ownerID: UUID, canPreflight: Bool, now: Date, container: ModelContainer,
                           isCurrent: () -> Bool) throws -> [Candidate] {
        let owner = ownerID.uuidString.lowercased(), kind = "reanalysis", context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
            $0.workKindRaw == kind && $0.reanalysisOwnerAccountID == owner
        }))
        var result: [Candidate] = []
        for row in rows {
            try Task.checkCancellation()
            guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
            guard case let .reanalysis(identity) = row.work, identity.ownerID == ownerID,
                  let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id)),
                  let metadata = job.metadataJSON, (try? Work.decode(Data(metadata.utf8))) != nil else { continue }
            do {
                let saved = try read(identity, container: container, isCurrent: isCurrent)
                guard let due = saved.work.due(now: now, canPreflight: canPreflight) else { continue }
                let admission: Admission
                switch saved.work.state {
                case .pending: admission = .initial
                case .waiting: admission = .dueRetry
                case .running: admission = .interrupted
                case .held: continue
                }
                result.append(.init(snapshot: saved, admission: admission, due: due))
            } catch let error as Persistence.IntegrityError {
                if case .accountChanged = error { throw error }
            } catch is MerianError { continue } catch is ObservationHistoryError { continue }
        }
        return result.sorted {
            $0.due == $1.due ? $0.snapshot.identity.analysisID.uuidString < $1.snapshot.identity.analysisID.uuidString : $0.due < $1.due
        }
    }

    static func claim(_ expected: Snapshot, admission: Admission, now: Date, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        let work = expected.work
        switch admission {
        case .initial: guard work.state == .pending else { throw Persistence.IntegrityError.conflict }
        case .dueRetry: guard work.state == .waiting, let due = work.nextRetryAt, due <= now else { throw Persistence.IntegrityError.conflict }
        case .interrupted: guard work.state == .running else { throw Persistence.IntegrityError.conflict }
        }
        let updated = try Work(preparation: work.preparation, phase: work.phase, state: .running,
            attempt: work.attempt + 1, updatedAt: now)
        return try Claim(change(expected, to: updated, container: container, isCurrent: isCurrent, save: save))
    }

    @discardableResult
    static func validate(_ claim: Claim, container: ModelContainer, isCurrent: () -> Bool,
                         proof: ObservationReanalysisPreparationIntent.Verified? = nil) throws -> Snapshot {
        try Persistence.transaction(claim.snapshot.identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try matching(claim, proof: proof, context: context).snapshot
        }
    }

    static func settle(_ claim: Claim, as settlement: Settlement, now: Date, container: ModelContainer,
                       isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let work = claim.snapshot.work, updated: Work
        switch settlement {
        case let .waiting(due): updated = try .init(preparation: work.preparation, phase: work.phase, state: .waiting,
            attempt: work.attempt, updatedAt: now, nextRetryAt: due)
        case let .held(reason): updated = try .init(preparation: work.preparation, phase: work.phase, state: .held,
            attempt: work.attempt, updatedAt: now, hold: reason)
        }
        _ = try change(claim.snapshot, to: updated, container: container, isCurrent: isCurrent, save: save)
    }

    /// Only the complete-cohort verifier's locked commit callback may call this promotion.
    static func promoteVerifiedFiles(_ claim: Claim, proof: ObservationReanalysisPreparationIntent.Verified,
                                     container: ModelContainer, isCurrent: () -> Bool,
                                     save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard claim.snapshot.work.phase == .filesPending else { throw Persistence.IntegrityError.conflict }
        return try Persistence.transaction(claim.snapshot.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let pair = try matching(claim, proof: proof, context: context)
            return try write(.init(preparation: proof.pending, phase: .admissionPending), job: pair.job)
        }
    }

    /// Shared by the atomic transition into bound execution; caller already owns the persistence transaction.
    static func matching(_ claim: Claim, proof: ObservationReanalysisPreparationIntent.Verified?,
                         context: ModelContext) throws -> Pair {
        let pair = try pair(claim.snapshot.identity, context: context)
        guard pair.snapshot == claim.snapshot, pair.snapshot.work.state == .running else { throw Persistence.IntegrityError.conflict }
        if let proof {
            guard proof.pending == pair.snapshot.work.preparation else { throw Persistence.IntegrityError.conflict }
            try proof.validate(context: context)
        }
        return pair
    }

    /// Caller owns the deletion transaction. Running ownership must be retired before local discard.
    static func validateDiscard(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws {
        let snapshot = try pair(identity, context: context).snapshot
        guard snapshot.work.state != .running else { throw Persistence.IntegrityError.conflict }
    }

    private static func change(_ expected: Snapshot, to work: Work, container: ModelContainer, isCurrent: () -> Bool,
                               save: (ModelContext) throws -> Void) throws -> Snapshot {
        try Persistence.transaction(expected.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let pair = try pair(expected.identity, context: context)
            guard pair.snapshot == expected else { throw Persistence.IntegrityError.conflict }
            return try write(work, job: pair.job)
        }
    }
    private static func write(_ work: Work, job: OfflineJobRecord) throws -> Snapshot {
        guard let metadata = String(bytes: try work.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
        // Compare the exact persisted representation, including JSON timestamp precision.
        let persisted = try Work.decode(Data(metadata.utf8))
        job.metadataJSON = metadata
        return .init(work: persisted, metadata: metadata)
    }

    private static func pair(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws -> Pair {
        try Persistence.requireNoResultCollision(identity, context: context)
        guard let (row, job) = try Persistence.pair(identity, context: context), let metadata = job.metadataJSON else { throw Persistence.IntegrityError.unavailable }
        let work = try Work.decode(Data(metadata.utf8)), child = identity.analysisID.uuidString.lowercased()
        guard work.preparation.draft.identity == identity, row.work == .reanalysis(identity), row.id == child,
              row.inferenceImagePaths == work.preparation.draft.photoPaths, row.scanStateRaw == ScanQueueState.pending.rawValue,
              row.queueNeedsAttention, row.queueAttemptCount == 0, row.queueLastAttemptAt == nil, row.queueNextRetryAt == nil,
              row.queueLastErrorCode == nil, row.queueLastErrorMessage == nil, row.queueLastHTTPStatus == nil,
              row.queueLastServerStatus == nil, row.queueLastServerStage == nil, row.queueLastServerRetryAfter == nil, row.stagedR2Keys == nil,
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: child), job.subjectId == child,
              job.kindRaw == OfflineJobKind.observationReanalysisSync.rawValue, job.statusRaw == OfflineJobStatus.needsAttention.rawValue,
              job.attemptCount == 0, job.lastAttemptAt == nil, job.nextRunAt == nil, job.lastErrorCode == nil,
              job.lastErrorMessage == nil, job.lastHTTPStatus == nil, job.serverStatus == nil, job.serverStage == nil, job.serverRetryAfter == nil,
              job.updatedAt.timeIntervalSince1970.isFinite, row.queueUpdatedAt.timeIntervalSince1970.isFinite else { throw Persistence.IntegrityError.conflict }
        return .init(row: row, job: job, snapshot: .init(work: work, metadata: metadata))
    }
}
