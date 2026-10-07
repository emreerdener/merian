import Foundation
import SwiftData

/// Prepared local execution ownership. Never dispatches, charges, selects or deletes files.
@MainActor
enum ObservationReanalysisExecutionStore {
    private typealias Persistence = ObservationReanalysisPersistence
    enum Admission { case initial, dueRetry, interrupted }
    enum Hold: String, Sendable {
        case evidenceUnavailable = "reanalysis_evidence_unavailable"
        case consentRequired = "reanalysis_consent_required"
        case terminalFailure = "reanalysis_terminal_failure"
        case reconciliationRequired = "reanalysis_reconciliation_required"
        case retryLimit = "reanalysis_retry_limit"
    }
    enum Settlement { case waiting(until: Date, server: ObservationAnalysisReceipt.State?), held(Hold) }
    struct Snapshot: Equatable, Sendable {
        let intent: ObservationReanalysisIntent
        let dispatch: ObservationReanalysisIntent.Dispatch
        let status: OfflineJobStatus
        let attempt: Int
        let updatedAt: Date
        let lastAttempt: Date?
        let nextRun: Date?
        let hold: Hold?
        let server: ObservationAnalysisReceipt.State?
        var retirement: UUID?
    }
    struct Claim: Sendable {
        let snapshot: Snapshot
        var intent: ObservationReanalysisIntent { snapshot.intent }
        fileprivate init(snapshot: Snapshot) { self.snapshot = snapshot }
    }

    static func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                     isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            try validateNamespace(identity, context: context)
            guard let (row, job) = try Persistence.pair(identity, context: context) else { throw Persistence.IntegrityError.unavailable }
            return try snapshot(row, job)
        }
    }

    struct Candidate {
        let snapshot: Snapshot
        let admission: Admission
        let due: Date
    }

    /// Strict owner-qualified discovery. Damaged/held/draft work cannot become a timer or legacy job.
    static func candidates(ownerID: UUID, container: ModelContainer, isCurrent: () -> Bool) throws -> [Candidate] {
        let owner = ownerID.uuidString.lowercased(), kind = "reanalysis"
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
            $0.workKindRaw == kind && $0.reanalysisOwnerAccountID == owner
        }))
        var candidates: [Candidate] = []
        for row in rows {
            try Task.checkCancellation()
            guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
            guard case let .reanalysis(identity) = row.work, identity.ownerID == ownerID,
                  let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id)),
                  let metadata = job.metadataJSON,
                  let intent = try? ObservationReanalysisIntent.decode(Data(metadata.utf8)), intent.identity == identity else { continue }
            do {
                let saved = try read(identity, container: container, isCurrent: isCurrent)
                guard saved.retirement == nil else { continue } // Dedicated retirement ownership is required.
                switch saved.status {
                case .pending: candidates.append(.init(snapshot: saved, admission: .initial, due: saved.nextRun!))
                case .waiting: candidates.append(.init(snapshot: saved, admission: .dueRetry, due: saved.nextRun!))
                case .running: candidates.append(.init(snapshot: saved, admission: .interrupted, due: saved.lastAttempt!))
                default: break
                }
            } catch let error as Persistence.IntegrityError {
                if case .accountChanged = error { throw error }
                // Immutable malformed or deleted work requires explicit repair, not a one-second wake loop.
            } catch is ObservationHistoryError {
                continue
            } catch is MerianError {
                continue
            }
        }
        return candidates.sorted {
            $0.due == $1.due ? $0.snapshot.intent.request.analysisID.uuidString < $1.snapshot.intent.request.analysisID.uuidString : $0.due < $1.due
        }
    }

    /// Explicit submit admission, atomic with one-time processor binding. A saved draft alone is held.
    /// Replays preserve every already-admitted or attempted state, including remediation holds.
    static func bindAndAdmit(_ draft: ObservationReanalysisDraft, processor: IdentificationRecipientExpectation,
                             now: Date, container: ModelContainer, isCurrent: () -> Bool,
                             submissionProof: ObservationReanalysisPreparationIntent.Verified? = nil,
                             admissionClaim: ObservationReanalysisAdmissionStore.Claim? = nil,
                             save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard now.timeIntervalSince1970.isFinite else { throw Persistence.IntegrityError.conflict }
        if let submissionProof {
            guard submissionProof.pending.draft == draft, submissionProof.pending.action == .submit else { throw Persistence.IntegrityError.conflict }
        }
        let candidate = try draft.binding(processor: processor)
        return try Persistence.transaction(draft.identity, container: container, isCurrent: isCurrent, save: save) { context in
            try validateNamespace(draft.identity, context: context)
            try submissionProof?.validate(context: context)
            if let admissionClaim {
                guard admissionClaim.snapshot.identity == draft.identity, let submissionProof,
                      admissionClaim.snapshot.work.phase == .admissionPending else { throw Persistence.IntegrityError.conflict }
                let pair = try ObservationReanalysisAdmissionStore.matching(admissionClaim, proof: submissionProof, context: context)
                guard let metadata = String(bytes: try submissionProof.pending.readyData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
                pair.job.metadataJSON = metadata
            }
            guard let (row, job) = try Persistence.pair(draft.identity, context: context) else { throw Persistence.IntegrityError.unavailable }
            switch try Persistence.restoreDraft(draft, row: row, job: job) {
            case let .bound(stored):
                guard stored.intent == candidate else { throw Persistence.IntegrityError.conflict }
            case .draft:
                guard submissionProof == nil else { throw Persistence.IntegrityError.conflict }
                guard let metadata = String(bytes: try candidate.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
                job.metadataJSON = metadata
            case let .submitted(saved):
                guard let submissionProof, submissionProof.pending == saved.preparation else { throw Persistence.IntegrityError.conflict }
                guard let metadata = String(bytes: try candidate.storedData(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
                job.metadataJSON = metadata
            }
            let current = try snapshot(row, job)
            guard current.status == .needsAttention, current.attempt == 0, current.dispatch == .ready else { return current }
            job.status = .pending; job.nextRunAt = now; job.updatedAt = now
            mirror(job, into: row)
            return try snapshot(row, job)
        }
    }

    /// Explicit user retirement intent. Status supports requesting retirement, never local cleanup.
    /// Full-snapshot CAS invalidates every older execution claim before any retirement I/O.
    static func stageRetirement(_ expected: Snapshot, status: ObservationAnalysisExecutionStatus,
                                operationID: UUID, now: Date, container: ModelContainer, isCurrent: () -> Bool,
                                save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Snapshot {
        guard now.timeIntervalSince1970.isFinite, expected.retirement == nil, expected.dispatch != .ready,
              status.state == .admitted, status.ownerID == expected.intent.ownerID,
              status.request == ObservationAnalysisExecutionLookup(expected.intent.request) else {
            throw Persistence.IntegrityError.conflict
        }
        let bound = ObservationReanalysisIntent.Bound(intent: expected.intent, dispatch: expected.dispatch, retirement: operationID)
        guard let metadata = String(data: try bound.data(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
        return try Persistence.transaction(expected.intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(expected, context: context)
            let child = expected.intent.request.analysisID.uuidString.lowercased()
            guard try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == child })).isEmpty else {
                throw Persistence.IntegrityError.conflict
            }
            job.metadataJSON = metadata
            job.status = .waiting; job.nextRunAt = now; job.updatedAt = now; job.lastErrorCode = nil
            job.serverStatus = ObservationAnalysisReceipt.State.admitted.rawValue
            if job.attemptCount == 0 { job.attemptCount = 1; job.lastAttemptAt = now }
            mirror(job, into: row)
            return try snapshot(row, job)
        }
    }

    enum RetirementAdmission { case initial, interrupted, explicitRetry }
    struct RetirementClaim: Sendable {
        let snapshot: Snapshot
        let request: ObservationAnalysisRetirementRequest
        fileprivate init(_ snapshot: Snapshot) throws {
            guard let operation = snapshot.retirement else { throw Persistence.IntegrityError.conflict }
            self.snapshot = snapshot
            request = try .init(operationID: operation, execution: .init(snapshot.intent.request))
        }
    }

    /// Retirement retries retain the exact saved UUID and never invoke analyze.
    static func claimRetirement(_ expected: Snapshot, admission: RetirementAdmission, now: Date,
                                container: ModelContainer, isCurrent: () -> Bool,
                                save: (ModelContext) throws -> Void = { try $0.save() }) throws -> RetirementClaim {
        guard expected.retirement != nil, now.timeIntervalSince1970.isFinite, expected.attempt < Int.max else {
            throw Persistence.IntegrityError.conflict
        }
        return try Persistence.transaction(expected.intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(expected, context: context)
            switch admission {
            case .initial:
                guard expected.status == .waiting, let due = expected.nextRun, due <= now else { throw Persistence.IntegrityError.conflict }
            case .interrupted:
                guard expected.status == .running else { throw Persistence.IntegrityError.conflict }
            case .explicitRetry:
                guard expected.status == .needsAttention, expected.hold == .reconciliationRequired else { throw Persistence.IntegrityError.conflict }
            }
            job.status = .running; job.attemptCount += 1; job.lastAttemptAt = now; job.nextRunAt = nil
            job.updatedAt = now; job.lastErrorCode = nil
            mirror(job, into: row)
            return try RetirementClaim(snapshot(row, job))
        }
    }

    static func validateRetirement(_ claim: RetirementClaim, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Persistence.transaction(claim.snapshot.intent.identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            _ = try matching(claim.snapshot, context: context)
            guard claim.snapshot.status == .running else { throw Persistence.IntegrityError.conflict }
        }
    }

    /// Uncertainty holds without a timer. Only an explicit same-operation recovery may claim again.
    static func holdRetirement(_ claim: RetirementClaim, now: Date, container: ModelContainer,
                               isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard now.timeIntervalSince1970.isFinite else { throw Persistence.IntegrityError.conflict }
        try Persistence.transaction(claim.snapshot.intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(claim.snapshot, context: context)
            guard claim.snapshot.status == .running else { throw Persistence.IntegrityError.conflict }
            job.status = .needsAttention; job.nextRunAt = nil; job.lastErrorCode = Hold.reconciliationRequired.rawValue
            job.updatedAt = now; mirror(job, into: row)
        }
    }

    /// Typed remote proof, exact claim and child erasure authority commit together. No result is fabricated.
    static func completeRetirement(_ claim: RetirementClaim, proof: ObservationAnalysisRetirementReceipt,
                                   container: ModelContainer, isCurrent: () -> Bool,
                                   save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationReanalysisErasureReceipt {
        guard claim.snapshot.status == .running, proof.request == claim.request else { throw Persistence.IntegrityError.conflict }
        let identity = claim.snapshot.intent.identity
        let receipt = ObservationReanalysisErasureReceipt(ownerID: identity.ownerID, retirement: proof)
        if try retiredReplay(claim, receipt: receipt, container: container, isCurrent: isCurrent) { return receipt }
        return try Persistence.transaction(identity, container: container, isCurrent: isCurrent, save: save, settlingRetirement: proof) { context in
            let (row, job) = try matching(claim.snapshot, context: context)
            let child = identity.analysisID.uuidString.lowercased()
            guard try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == child })).isEmpty else {
                throw Persistence.IntegrityError.conflict
            }
            try receipt.record(in: context)
            try context.deletePreferredGoalHint(scanId: row.id)
            context.delete(job); context.delete(row)
            return receipt
        }
    }

    /// Dispatch may win the server retirement race. Recover only the original exact outcome.
    /// This is a result completion, never a successful retirement or another provider invocation.
    static func completeRetirementOutcome(_ claim: RetirementClaim, resultBytes: Data, container: ModelContainer,
                                          isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws
        -> ObservationReanalysisErasureReceipt {
        guard claim.snapshot.status == .running else { throw Persistence.IntegrityError.conflict }
        let intent = claim.snapshot.intent
        let result = try ObservationReanalysisResult.decode(resultBytes, matching: intent.request)
        let receipt = ObservationReanalysisErasureReceipt(ownerID: intent.ownerID, completedRetirement: claim.request)
        if try completedReplay(intent, result: result, receipt: receipt, container: container, isCurrent: isCurrent) { return receipt }
        return try Persistence.transaction(intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(claim.snapshot, context: context)
            let parent = try ObservationHistorySyncService.enrolledScan(intent.identity.observationID.uuidString, context: context)
            _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: intent.ownerID, context: context)
            try receipt.record(in: context)
            try context.deletePreferredGoalHint(scanId: row.id)
            context.delete(job); context.delete(row)
            return receipt
        }
    }

    private static func retiredReplay(_ claim: RetirementClaim, receipt: ObservationReanalysisErasureReceipt,
                                      container: ModelContainer, isCurrent: () -> Bool) throws -> Bool {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            let identity = claim.snapshot.intent.identity
            try validateNamespace(identity, context: context)
            guard let job = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(identity.analysisID)) else { return false }
            let parent = try ObservationHistorySyncService.enrolledScan(identity.observationID.uuidString, context: context)
            let child = identity.analysisID.uuidString.lowercased()
            guard parent.analysisOwnerAccountID == identity.ownerID.uuidString.lowercased(),
                  try ObservationReanalysisErasureReceipt.restore(job) == receipt,
                  try Persistence.pair(identity, context: context) == nil,
                  try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == child })).isEmpty,
                  isCurrent() else { throw Persistence.IntegrityError.conflict }
            return true
        }
    }

    /// `interrupted` is for a replacement execution owner after draining its old tasks.
    /// Every new claim advances the persisted attempt fence, including exact-request recovery.
    static func claim(_ expected: Snapshot, admission: Admission, now: Date, container: ModelContainer,
                      isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        guard expected.retirement == nil, now.timeIntervalSince1970.isFinite, expected.attempt < Int.max else { throw Persistence.IntegrityError.conflict }
        return try Persistence.transaction(expected.intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(expected, context: context)
            switch admission {
            case .initial:
                guard expected.status == .pending, expected.attempt == 0, let due = expected.nextRun, due <= now else { throw Persistence.IntegrityError.conflict }
            case .dueRetry:
                guard expected.status == .waiting, let due = expected.nextRun, due <= now else { throw Persistence.IntegrityError.conflict }
            case .interrupted:
                guard expected.status == .running else { throw Persistence.IntegrityError.conflict }
            }
            job.status = .running; job.attemptCount += 1; job.lastAttemptAt = now; job.nextRunAt = nil
            job.updatedAt = now; job.lastErrorCode = nil
            mirror(job, into: row)
            return Claim(snapshot: try snapshot(row, job))
        }
    }

    /// Commit before analyze; a throwing save never yields dispatch permission.
    /// The new full snapshot invalidates the pre-consumption claim immediately.
    static func consumeDispatch(_ claim: Claim, container: ModelContainer, isCurrent: () -> Bool,
                                save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Claim {
        try Persistence.transaction(claim.intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(claim.snapshot, context: context)
            guard claim.snapshot.retirement == nil, claim.snapshot.status == .running, claim.snapshot.dispatch == .ready else { throw Persistence.IntegrityError.conflict }
            let bound = ObservationReanalysisIntent.Bound(intent: claim.intent, dispatch: .consumed(attempt: claim.snapshot.attempt))
            guard let metadata = String(data: try bound.data(), encoding: .utf8) else { throw Persistence.IntegrityError.conflict }
            job.metadataJSON = metadata
            return Claim(snapshot: try snapshot(row, job))
        }
    }

    static func validate(_ claim: Claim, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Persistence.transaction(claim.intent.identity, container: container, isCurrent: isCurrent, save: { try $0.save() }) { context in
            _ = try matching(claim.snapshot, context: context)
            guard claim.snapshot.retirement == nil, claim.snapshot.status == .running else { throw Persistence.IntegrityError.conflict }
        }
    }

    /// Uncertainty schedules the same immutable request. Terminal provider failure retains evidence for explicit remediation.
    static func settle(_ claim: Claim, as settlement: Settlement, now: Date, container: ModelContainer,
                       isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard now.timeIntervalSince1970.isFinite else { throw Persistence.IntegrityError.conflict }
        try Persistence.transaction(claim.intent.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(claim.snapshot, context: context)
            guard claim.snapshot.retirement == nil, job.status == .running else { throw Persistence.IntegrityError.conflict }
            switch settlement {
            case let .waiting(until, server):
                guard until.timeIntervalSince1970.isFinite, until > now, server != .failedTerminal,
                      claim.snapshot.dispatch != .ready || server == nil else { throw Persistence.IntegrityError.conflict }
                job.status = .waiting; job.nextRunAt = until; job.lastErrorCode = nil; job.serverStatus = server?.rawValue
            case let .held(reason):
                job.status = .needsAttention; job.nextRunAt = nil; job.lastErrorCode = reason.rawValue
                if reason == .terminalFailure { job.serverStatus = ObservationAnalysisReceipt.State.failedTerminal.rawValue }
            }
            job.updatedAt = now
            mirror(job, into: row)
        }
    }

    /// Append, retire transport work and retain cleanup authority in one save. Selection is untouched.
    /// Exact committed replay is checked before the normal erasure fence; deletion still wins.
    static func complete(_ claim: Claim, resultBytes: Data, container: ModelContainer,
                         isCurrent: () -> Bool, save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationReanalysisErasureReceipt {
        guard claim.snapshot.retirement == nil else { throw Persistence.IntegrityError.conflict }
        let result = try ObservationReanalysisResult.decode(resultBytes, matching: claim.intent.request)
        let identity = claim.intent.identity
        let receipt = ObservationReanalysisErasureReceipt(parentID: identity.observationID, childID: identity.analysisID)
        if try completedReplay(claim.intent, result: result, receipt: receipt, container: container, isCurrent: isCurrent) { return receipt }
        return try Persistence.transaction(identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try matching(claim.snapshot, context: context)
            guard claim.snapshot.retirement == nil, job.status == .running else { throw Persistence.IntegrityError.conflict }
            let parent = try ObservationHistorySyncService.enrolledScan(identity.observationID.uuidString, context: context)
            _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: identity.ownerID, context: context)
            try receipt.record(in: context)
            try context.deletePreferredGoalHint(scanId: row.id)
            context.delete(job); context.delete(row)
            return receipt
        }
    }

    private static func completedReplay(_ intent: ObservationReanalysisIntent, result: ObservationHistoryPage.Result,
                                        receipt: ObservationReanalysisErasureReceipt, container: ModelContainer,
                                        isCurrent: () -> Bool) throws -> Bool {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try Task.checkCancellation()
            guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
            let context = ModelContext(container); context.autosaveEnabled = false
            try validateNamespace(intent.identity, context: context)
            guard let job = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID)) else { return false }
            let parent = try ObservationHistorySyncService.enrolledScan(receipt.parentID.uuidString, context: context)
            guard parent.analysisOwnerAccountID == intent.ownerID.uuidString.lowercased(),
                  try ObservationReanalysisErasureReceipt.restore(job) == receipt,
                  try Persistence.pair(intent.identity, context: context) == nil else { throw Persistence.IntegrityError.conflict }
            let id = receipt.childID.uuidString.lowercased(), upper = receipt.childID.uuidString
            let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id || $0.id == upper }))
            guard records.count == 1, let record = records.first, record.id == id,
                  record.ownerAccountID == parent.analysisOwnerAccountID, record.observationID == parent.id,
                  record.snapshotVersion == result.version, record.completedAt == result.completedAt,
                  record.resultSnapshotData == result.bytes else { throw Persistence.IntegrityError.conflict }
            try Task.checkCancellation()
            guard isCurrent() else { throw Persistence.IntegrityError.accountChanged }
            return true
        }
    }

    private static func matching(_ expected: Snapshot, context: ModelContext) throws -> (OfflineQueuedScan, OfflineJobRecord) {
        try validateNamespace(expected.intent.identity, context: context)
        guard let (row, job) = try Persistence.pair(expected.intent.identity, context: context),
              try snapshot(row, job) == expected else { throw Persistence.IntegrityError.conflict }
        return (row, job)
    }

    private static func snapshot(_ row: OfflineQueuedScan, _ job: OfflineJobRecord) throws -> Snapshot {
        let stored = try Persistence.restore(row: row, job: job)
        guard row.scanStateRaw == ScanQueueState.pending.rawValue, row.stagedR2Keys == nil,
              row.queueAttemptCount == job.attemptCount, row.queueLastAttemptAt == job.lastAttemptAt,
              row.queueNextRetryAt == job.nextRunAt, row.queueLastErrorCode == job.lastErrorCode,
              row.queueLastServerStatus == job.serverStatus, row.queueNeedsAttention == (stored.status == .needsAttention),
              job.updatedAt.timeIntervalSince1970.isFinite, row.queueUpdatedAt.timeIntervalSince1970.isFinite,
              (job.attemptCount == 0 && stored.status == .needsAttention) || row.queueUpdatedAt == job.updatedAt,
              row.queueLastErrorMessage == nil, row.queueLastHTTPStatus == nil, row.queueLastServerStage == nil,
              row.queueLastServerRetryAfter == nil, job.lastErrorMessage == nil, job.lastHTTPStatus == nil,
              job.serverStage == nil, job.serverRetryAfter == nil,
              job.lastAttemptAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              job.nextRunAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw Persistence.IntegrityError.conflict }
        if case let .consumed(attempt) = stored.dispatch {
            guard attempt <= job.attemptCount, job.attemptCount > 0 else { throw Persistence.IntegrityError.conflict }
        }
        let hold = job.lastErrorCode.flatMap(Hold.init(rawValue:)), server = job.serverStatus.flatMap(ObservationAnalysisReceipt.State.init(rawValue:))
        guard job.lastErrorCode == hold?.rawValue, job.serverStatus == server?.rawValue else { throw Persistence.IntegrityError.conflict }
        if stored.dispatch == .ready, stored.status != .needsAttention {
            guard server == nil else { throw Persistence.IntegrityError.conflict }
        }
        if stored.retirement != nil {
            guard stored.dispatch != .ready, server == .admitted,
                  [.waiting, .running, .needsAttention].contains(stored.status) else { throw Persistence.IntegrityError.conflict }
        }
        switch stored.status {
        case .needsAttention:
            guard job.nextRunAt == nil,
                  job.attemptCount == 0 ? (job.lastAttemptAt == nil && hold == nil && server == nil) : (job.lastAttemptAt != nil && hold != nil) else {
                throw Persistence.IntegrityError.conflict
            }
        case .pending:
            guard job.attemptCount == 0, job.lastAttemptAt == nil, job.nextRunAt != nil,
                  hold == nil, server == nil else { throw Persistence.IntegrityError.conflict }
        case .running, .waiting:
            guard job.attemptCount > 0, job.lastAttemptAt != nil, hold == nil, server != .failedTerminal,
                  (stored.status == .running) == (job.nextRunAt == nil) else { throw Persistence.IntegrityError.conflict }
        default: throw Persistence.IntegrityError.conflict
        }
        return Snapshot(intent: stored.intent, dispatch: stored.dispatch, status: stored.status, attempt: job.attemptCount, updatedAt: job.updatedAt,
            lastAttempt: job.lastAttemptAt, nextRun: job.nextRunAt, hold: hold, server: server, retirement: stored.retirement)
    }

    /// Ambiguous legacy aliases and a deletion marker always win. A canonical history result
    /// may arrive from owner sync first; insertion still verifies its complete immutable bytes.
    private static func validateNamespace(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws {
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

    private static func mirror(_ job: OfflineJobRecord, into row: OfflineQueuedScan) {
        row.queueAttemptCount = job.attemptCount; row.queueLastAttemptAt = job.lastAttemptAt
        row.queueNextRetryAt = job.nextRunAt; row.queueLastErrorCode = job.lastErrorCode
        row.queueLastServerStatus = job.serverStatus; row.queueUpdatedAt = job.updatedAt
        row.queueNeedsAttention = job.status == .needsAttention
    }
}
