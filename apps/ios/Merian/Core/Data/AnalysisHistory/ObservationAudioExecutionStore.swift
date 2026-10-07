import Foundation
import SwiftData

/// Inert exact-byte audio ownership. No scheduler, HTTP, funding, selection or file effects.
@MainActor
enum ObservationAudioExecutionStore {
    private typealias Persistence = ObservationReanalysisPersistence
    typealias Work = ObservationAudioExecutionIntent.Work
    struct Snapshot: Equatable, Sendable {
        let work: Work
        let metadata: String
    }
    struct Claim: Sendable {
        let snapshot: Snapshot
        fileprivate init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }
    /// Only a successful consume save can construct this capability; recovery cannot acquire one.
    struct DispatchPermit: Sendable {
        let claim: Claim
        var snapshot: Snapshot { claim.snapshot }
        fileprivate init(_ snapshot: Snapshot) { claim = Claim(snapshot) }
    }
    enum Purpose { case initial, recovery }

    /// The caller prepares the candidate off-main and synchronizes current fixed-Gemini consent.
    /// Authorization may itself read durable state, so it runs before taking the persistence lock.
    static func bind(_ candidate: ObservationAudioExecutionIntent, proof: ObservationAudioPreparation.Verified,
                     authorization: IdentificationDispatchAuthorization, container: ModelContainer, isCurrent: () -> Bool,
                     save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard candidate.matches(proof.preparation) else { throw Persistence.IntegrityError.conflict }
        if let saved = try existingBinding(proof, container: container, isCurrent: isCurrent) {
            guard saved.work.intent == candidate else { throw Persistence.IntegrityError.conflict }
            return saved
        }
        guard authorization.recipient == .gemini else { throw Persistence.IntegrityError.conflict }
        try authorization.validate()
        return try Persistence.transaction(candidate.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            guard let (row, job) = try Persistence.pair(candidate.identity, context: context), let metadata = job.metadataJSON else {
                throw Persistence.IntegrityError.unavailable
            }
            if (try? Work.decode(Data(metadata.utf8))) != nil {
                let saved = try snapshot(proof, row: row, job: job)
                guard saved.work.intent == candidate else { throw Persistence.IntegrityError.conflict }
                return saved
            }
            guard try ObservationAudioPreparationStore.restore(proof.preparation, row: row, job: job) == .admissionPending else {
                throw Persistence.IntegrityError.conflict
            }
            return try write(Work(intent: candidate), proof: proof, row: row, job: job)
        }
    }

    /// Exact persisted recovery is independent of current inference consent; it never returns dispatch permission.
    static func read(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer, isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try proof.validate(context: context)
            guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context) else {
                throw Persistence.IntegrityError.unavailable
            }
            return try snapshot(proof, row: row, job: job)
        }
    }

    /// Every retained owner advances the CAS generation. Only unconsumed work can claim a first invocation.
    /// Recovery claims may only read/reconcile; they never reset the original consumed marker.
    static func claim(_ expected: Snapshot, purpose: Purpose, proof: ObservationAudioPreparation.Verified,
                      container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        let eligible = purpose == .initial
            ? expected.work.state == .idle && expected.work.consumedAttempt == nil
            : expected.work.state == .held && expected.work.consumedAttempt != nil
        guard eligible, expected.work.attempt < 2_147_483_647 else {
            throw Persistence.IntegrityError.conflict
        }
        return try Claim(change(expected, proof: proof, container: container, isCurrent: isCurrent, save: save) { saved in
            try Work(intent: saved.intent, state: .running, attempt: saved.attempt + 1, consumedAttempt: saved.consumedAttempt)
        })
    }

    /// Only explicit fresh authorization may resume a held attempt proven not to have consumed dispatch.
    static func resumeUndispatched(_ expected: Snapshot, proof: ObservationAudioPreparation.Verified,
                                   authorization: IdentificationDispatchAuthorization, container: ModelContainer,
                                   isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        guard expected.work.state == .held, expected.work.consumedAttempt == nil,
              expected.work.attempt < 2_147_483_647, authorization.recipient == .gemini else { throw Persistence.IntegrityError.conflict }
        try authorization.validate()
        return try Claim(change(expected, proof: proof, container: container, isCurrent: isCurrent, save: save) { saved in
            try Work(intent: saved.intent, state: .running, attempt: saved.attempt + 1)
        })
    }

    /// Save before any potentially dispatching call. A throwing save yields no permission, even if committed.
    /// The returned snapshot invalidates the pre-consumption claim immediately.
    static func consume(_ claim: Claim, proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                        isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> DispatchPermit {
        guard claim.snapshot.work.state == .running, claim.snapshot.work.consumedAttempt == nil else { throw Persistence.IntegrityError.conflict }
        return try DispatchPermit(change(claim.snapshot, proof: proof, container: container, isCurrent: isCurrent, save: save) { saved in
            try Work(intent: saved.intent, state: .running, attempt: saved.attempt, consumedAttempt: saved.attempt)
        })
    }

    static func validateDispatch(_ permit: DispatchPermit, proof: ObservationAudioPreparation.Verified,
                                 container: ModelContainer, isCurrent: () -> Bool) throws {
        guard permit.snapshot.work.consumedAttempt == permit.snapshot.work.attempt else { throw Persistence.IntegrityError.conflict }
        try validate(permit.claim, proof: proof, container: container, isCurrent: isCurrent)
    }

    /// Settlement/ownership only; this does not authorize dispatch.
    static func validate(_ claim: Claim, proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                         isCurrent: () -> Bool) throws {
        guard claim.snapshot.work.state == .running else { throw Persistence.IntegrityError.conflict }
        let saved = try read(proof, container: container, isCurrent: isCurrent)
        guard saved == claim.snapshot else { throw Persistence.IntegrityError.conflict }
    }

    /// Cancellation and uncertainty hold without a deadline; no automatic replay or replacement.
    static func hold(_ claim: Claim, proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                     isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard claim.snapshot.work.state == .running else { throw Persistence.IntegrityError.conflict }
        _ = try change(claim.snapshot, proof: proof, container: container, isCurrent: isCurrent, save: save) { saved in
            try Work(intent: saved.intent, state: .held, attempt: saved.attempt, consumedAttempt: saved.consumedAttempt)
        }
    }

    /// Settlement only: a known exact outcome may survive task cancellation, never account or claim loss.
    /// The raw result, queue retirement and cleanup receipt commit together; selection is untouched.
    static func complete(_ claim: Claim, resultBytes: Data, proof: ObservationAudioPreparation.Verified,
                         container: ModelContainer, isCurrent: () -> Bool,
                         save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationReanalysisErasureReceipt {
        let intent = claim.snapshot.work.intent, identity = intent.identity
        guard claim.snapshot.work.state == .running, claim.snapshot.work.consumedAttempt != nil,
              intent.matches(proof.preparation) else { throw Persistence.IntegrityError.conflict }
        let result = try ObservationReanalysisResult.decode(resultBytes, matching: intent.request)
        let receipt = ObservationReanalysisErasureReceipt(parentID: identity.observationID, childID: identity.analysisID)
        // Do not use the generic dispatch transaction's cancellation check for a received outcome.
        return try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                try proof.validate(context: context)
                try completionNamespace(identity, context: context)
                let parent = try ObservationHistorySyncService.enrolledScan(identity.observationID.uuidString, context: context)
                if let erased = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(identity.analysisID)) {
                    guard try ObservationReanalysisErasureReceipt.restore(erased) == receipt,
                          try Persistence.pair(identity, context: context) == nil else { throw Persistence.IntegrityError.conflict }
                    let child = identity.analysisID.uuidString.lowercased()
                    let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == child }))
                    guard records.count == 1, let record = records.first, record.ownerAccountID == identity.ownerID.uuidString.lowercased(),
                          record.observationID == parent.id, record.snapshotVersion == result.version,
                          record.completedAt == result.completedAt, record.resultSnapshotData == result.bytes else {
                        throw Persistence.IntegrityError.conflict
                    }
                } else {
                    guard let (row, job) = try Persistence.pair(identity, context: context),
                          try snapshot(proof, row: row, job: job) == claim.snapshot else { throw Persistence.IntegrityError.conflict }
                    _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: identity.ownerID, context: context)
                    try receipt.record(in: context)
                    try context.deletePreferredGoalHint(scanId: row.id)
                    context.delete(job); context.delete(row)
                }
                guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
                if context.hasChanges { try save(context) }
                return receipt
            } catch { context.rollback(); throw error }
        }
    }

    private static func completionNamespace(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws {
        let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
        guard try context.fetch(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty,
              try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty,
              !(try ObservationHistoryEnrollmentIntent.holds(lower, context: context)) else { throw Persistence.IntegrityError.conflict }
        if upper != lower {
            guard try context.fetchOfflineJob(id: "reanalysis-erasure:" + upper) == nil,
                  try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: upper)) == nil,
                  try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == upper })).isEmpty else {
                throw Persistence.IntegrityError.conflict
            }
        }
    }

    private static func existingBinding(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                                        isCurrent: () -> Bool) throws -> Snapshot? {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try proof.validate(context: context)
            guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context), let metadata = job.metadataJSON else {
                throw Persistence.IntegrityError.unavailable
            }
            guard (try? Work.decode(Data(metadata.utf8))) != nil else { return nil }
            return try snapshot(proof, row: row, job: job)
        }
    }

    private static func change(_ expected: Snapshot, proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                               isCurrent: () -> Bool, save: (ModelContext) throws -> Void,
                               update: (Work) throws -> Work) throws -> Snapshot {
        try Persistence.transaction(proof.preparation.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try proof.validate(context: context)
            guard let (row, job) = try Persistence.pair(proof.preparation.identity, context: context),
                  try snapshot(proof, row: row, job: job) == expected else { throw Persistence.IntegrityError.conflict }
            return try write(update(expected.work), proof: proof, row: row, job: job)
        }
    }

    private static func snapshot(_ proof: ObservationAudioPreparation.Verified, row: OfflineQueuedScan, job: OfflineJobRecord) throws -> Snapshot {
        try ObservationAudioPreparationStore.validateRow(proof.preparation, row: row, job: job)
        guard let metadata = job.metadataJSON else { throw Persistence.IntegrityError.conflict }
        let work = try Work.decode(Data(metadata.utf8))
        guard work.intent.matches(proof.preparation) else { throw Persistence.IntegrityError.conflict }
        return Snapshot(work: work, metadata: metadata)
    }

    private static func write(_ work: Work, proof: ObservationAudioPreparation.Verified, row: OfflineQueuedScan,
                              job: OfflineJobRecord) throws -> Snapshot {
        guard let metadata = String(data: try work.data(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
        job.metadataJSON = metadata
        return try snapshot(proof, row: row, job: job)
    }
}
