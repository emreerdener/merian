import Foundation
import Supabase
import SwiftData

/// Durable, account-bound outbox. No optimistic decision manufactures server authority.
@MainActor
struct IdentificationReviewSyncService {
    private struct HistoryProtected: Error {}
    private struct ReconcileOnly: Error {}
    struct JobPayload: Codable {
        let ownerID: UUID
        let request: AIIdentificationReviewRequest
    }
    @MainActor struct Dependencies {
        var loadPendingJobs: (ModelContext, FetchDescriptor<OfflineJobRecord>) throws -> [OfflineJobRecord] = {
            try $0.fetch($1)
        }
        var beginWork: () throws -> AccountBoundWorkLease = { try SupabaseManager.shared.beginUnownedAccountBoundWork() }
        var finishWork: (AccountBoundWorkLease) -> Void = { SupabaseManager.shared.finishAccountBoundWork($0) }
        var isWorkCurrent: (AccountBoundWorkLease) -> Bool = { SupabaseManager.shared.isAccountBoundWorkLeaseCurrent($0) }
        var didAccept: (String) async -> Void = { scanID in
            await AppDIContainer.shared.scanMilestoneCoordinator.processIdentificationUpdate(scanId: scanID)
            if let postID = ExploreShareStateStore.sharedPostId(for: scanID) {
                AppDIContainer.shared.appEventPublisher.send(.explorePostNeedsRefresh(postId: postID))
            }
        }
        var retireSource: (LocalScanRecord, ModelContext) -> Void = {
            ScanRepository.shared.eradicateScan(record: $0, modelContext: $1, origin: .reanalysisReplacement)
        }

        var fetchLatest: (String) async throws -> AIIdentificationReviewSnapshot = { try await .fetch(scanID: $0) }
        var allowsMutation: () -> Bool = { SupabaseManager.shared.allowsLocalLibraryMutation }
        var ownerID: () -> UUID? = { SupabaseManager.shared.currentUser?.id }
        var submit: (AIIdentificationReviewRequest) async throws -> AIIdentificationReviewReceipt = {
            try await MerianNetworkClient.shared.reviewScanIdentification($0)
        }
    }
    var dependencies = Dependencies()

    func enqueue(scanID: String, action: AIIdentificationReviewRequest.Action, scientificName: String? = nil,
                 context: ModelContext, expectedReview: LocalAIIdentificationReview? = nil) throws -> LocalAIIdentificationReview {
        guard dependencies.allowsMutation(), let ownerID = dependencies.ownerID() else { throw ConfirmedSpeciesReview.IntegrityError.invalidRequest }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            // Use a fresh context so a review cannot commit unrelated presentation edits.
            let write = ModelContext(context.container)
            write.autosaveEnabled = false
            try Self.requireLegacy(scanID: scanID, context: write)
            guard let scan = try Self.record(scanID, context: write) else { throw ConfirmedSpeciesReview.IntegrityError.missingRecord }
            var local = scan.localAIIdentificationReview
            guard !local.needsAttention else { throw ConfirmedSpeciesReview.IntegrityError.conflictingRevision }
            // Compare inside the write transaction; displayed authority can lag a durable review change.
            guard expectedReview == nil || local == expectedReview else { throw ConfirmedSpeciesReview.IntegrityError.conflictingRevision }
            let expectedRevision = local.pending.map { $0.expectedRevision + 1 } ?? local.authority?.revision ?? 0
            let expectedSpeciesRevision = local.pending?.expectedSpeciesReviewRevision.map { $0 + 1 }
            let verified = try ConfirmedSpeciesReview.restoring(scan.confirmedSpeciesIdentityData)
            let request = AIIdentificationReviewRequest(scanID: scanID.lowercased(), expectedRevision: expectedRevision,
                operationID: UUID().uuidString.lowercased(), action: action, scientificName: scientificName,
                expectedSpeciesReviewRevision: scan.primaryIdentificationData == nil ? nil : expectedSpeciesRevision ?? verified?.revision ?? 0)
            if action == .reject {
                local.optimisticState = .aiRejected
            } else if action == .undo {
                local.optimisticState = .clear
            } else if local.isUnresolved {
                local.optimisticState = .awaitingAcceptance
            }
            if action == .reject || action == .undo {
                scan.userConfirmedIdentification = false
            }
            local.pending = request; local.needsAttention = false; local.conflictReconciled = false
            scan.aiIdentificationReviewData = try local.storedData()
            let payload = try JSONEncoder().encode(JobPayload(ownerID: ownerID, request: request))
            _ = try write.ensureOfflineJobRecord(id: "identification-review:\(request.operationID)", kind: .identificationReviewSync,
                subjectId: scanID, priority: 70, metadataJSON: String(bytes: payload, encoding: .utf8))
            try write.save()
            return local
        }
    }

    func carryRejection(from source: LocalScanRecord, to replacement: LocalScanRecord, context: ModelContext,
                        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try Self.requireLegacy(scanID: source.id, context: ModelContext(context.container))
            try Self.requireLegacy(scanID: replacement.id, context: ModelContext(context.container))
            guard dependencies.allowsMutation() else { throw ConfirmedSpeciesReview.IntegrityError.invalidRequest }
            let state = source.localAIIdentificationReview
            guard state.isUnresolved, state.pending == nil, !state.needsAttention,
                  let authority = state.authority, let ownerID = dependencies.ownerID() else {
                throw ConfirmedSpeciesReview.IntegrityError.conflictingRevision
            }
            let request = AIIdentificationReviewRequest(scanID: replacement.id.lowercased(), expectedRevision: 0,
                operationID: UUID().uuidString.lowercased(), action: .carry, scientificName: nil,
                expectedSpeciesReviewRevision: replacement.primaryIdentificationData == nil ? nil : 0,
                sourceScanID: source.id.lowercased(), sourceRevision: authority.revision)
            let priorReview = replacement.aiIdentificationReviewData
            var stagedJob: OfflineJobRecord?
            do {
                replacement.aiIdentificationReviewData = try LocalAIIdentificationReview(pending: request, optimisticState: .awaitingAcceptance).storedData()
                let payload = try JSONEncoder().encode(JobPayload(ownerID: ownerID, request: request))
                stagedJob = try context.ensureOfflineJobRecord(id: "identification-review:\(request.operationID)", kind: .identificationReviewSync,
                    subjectId: replacement.id, priority: 70, metadataJSON: String(bytes: payload, encoding: .utf8))
                try save(context)
            } catch {
                replacement.aiIdentificationReviewData = priorReview
                if let stagedJob { context.delete(stagedJob) }
                throw error
            }
        }
    }

    func drain(context: ModelContext) async {
        do {
            try await drainPending(context: context)
        } catch {
            MerianLog.data.error("Identification review persistence failed; durable work remains retryable.")
        }
    }

    private func drainPending(context: ModelContext) async throws {
        let write = ModelContext(context.container)
        write.autosaveEnabled = false
        let kind = OfflineJobKind.identificationReviewSync.rawValue
        var descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.kindRaw == kind }, sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 100
        let jobs = try dependencies.loadPendingJobs(write, descriptor)
        var blockedSubjects = Set<String?>()
        for job in jobs {
            guard !Task.isCancelled else { return }
            guard !blockedSubjects.contains(job.subjectId) else { continue }
            if job.status == .needsAttention || !(job.nextRunAt.map({ $0 <= Date() }) ?? true) {
                blockedSubjects.insert(job.subjectId); continue
            }
            guard [.pending, .waiting, .running].contains(job.status),
                  let text = job.metadataJSON,
                  let payload = try? JSONDecoder().decode(JobPayload.self, from: Data(text.utf8)),
                  dependencies.ownerID() == payload.ownerID else { continue }
            guard let lease = try? dependencies.beginWork() else { return }
            defer { dependencies.finishWork(lease) }
            guard dependencies.isWorkCurrent(lease), dependencies.ownerID() == payload.ownerID else { return }
            do {
                let admitted = try Self.withLegacyWrite(container: context.container, request: payload.request) { write in
                    guard let currentJob = try write.fetchOfflineJob(id: job.id) else { return false }
                    guard try Self.record(payload.request.scanID, context: write) != nil else {
                        write.delete(currentJob); try write.save(); return false
                    }
                    if currentJob.lastErrorCode == "identification_review_reconcile" { throw ReconcileOnly() }
                    currentJob.status = .running; currentJob.nextRunAt = nil
                    currentJob.attemptCount += 1; currentJob.lastAttemptAt = Date()
                    try write.save()
                    return true
                }
                guard admitted else { continue }
                let receipt = try await dependencies.submit(payload.request)
                guard dependencies.isWorkCurrent(lease), dependencies.ownerID() == payload.ownerID else { return }
                let committed = try Self.withLegacyWrite(container: context.container, request: payload.request) { commit in
                    guard let current = try Self.record(payload.request.scanID, context: commit),
                          let currentJob = try commit.fetchOfflineJob(id: job.id) else { return false }
                    var currentState = current.localAIIdentificationReview
                    currentState.authority = try AIIdentificationReview.merging(stored: currentState.authority, incoming: receipt.review)
                    if currentState.pending == payload.request {
                        currentState.pending = nil; currentState.optimisticState = nil
                    }
                    current.aiIdentificationReviewData = try currentState.storedData()
                    if let review = receipt.speciesReview {
                        current.confirmedSpeciesIdentityData = try review.storedData()
                        current.userIdentificationOverride = review.userIdentificationOverride
                        current.userConfirmedIdentification = review.userConfirmedIdentification
                        current.confirmedSpeciesId = review.confirmedSpeciesID
                        current.userReviewState = review.userReviewState
                    } else {
                        current.userConfirmedIdentification = payload.request.action == .confirmPrimary
                        current.userIdentificationOverride = payload.request.action == .confirmName ? payload.request.scientificName : nil
                        current.confirmedSpeciesId = receipt.confirmedSpeciesID
                        current.userReviewState = payload.request.action == .confirmPrimary ? .aiConfirmed : payload.request.action == .confirmName ? .userOverridden : .unreviewed
                    }
                    commit.delete(currentJob)
                    try commit.save()
                    return true
                }
                guard committed else { continue }
                let commit = ModelContext(context.container)
                await dependencies.didAccept(payload.request.scanID)
                if dependencies.isWorkCurrent(lease), dependencies.ownerID() == payload.ownerID, payload.request.action == .carry, let sourceID = payload.request.sourceScanID,
                   let original = try Self.record(sourceID, context: commit),
                   ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: sourceID, container: context.container),
                   ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: payload.request.scanID, container: context.container),
                   original.localAIIdentificationReview.pending == nil,
                   original.localAIIdentificationReview.authority?.revision == payload.request.sourceRevision {
                    dependencies.retireSource(original, commit)
                }
            } catch is HistoryProtected {
                try Self.holdProtectedJob(job.id, container: context.container)
                blockedSubjects.insert(job.subjectId)
            } catch {
                guard dependencies.isWorkCurrent(lease) else { return }
                let code = EdgeFunctionErrorPolicy.stableCode(from: error)
                if code == "analysis_bound_review_required" {
                    try Self.holdProtectedJob(job.id, container: context.container)
                    blockedSubjects.insert(job.subjectId)
                    continue
                }
                let isConflict = code == "identification_review_revision_conflict" || error is ReconcileOnly
                let permanent = ["invalid_identification_review", "species_not_verified", "identification_review_not_found"].contains(code ?? "")
                do {
                    try Self.withLegacyWrite(container: context.container, request: payload.request) { failed in
                        guard let currentJob = try failed.fetchOfflineJob(id: job.id) else { return }
                        // Later operations for this scan depend on this exact revision.
                        // A failed predecessor must never allow its successor to overtake it.
                        if isConflict || permanent {
                            currentJob.status = .waiting; currentJob.nextRunAt = Date().addingTimeInterval(30)
                            if let scan = try Self.record(payload.request.scanID, context: failed) {
                                var state = scan.localAIIdentificationReview; state.needsAttention = true
                                scan.aiIdentificationReviewData = try state.storedData()
                            }
                        } else {
                            currentJob.status = .waiting
                            currentJob.nextRunAt = Date().addingTimeInterval(min(300, pow(2, Double(min(currentJob.attemptCount, 8)))))
                        }
                        currentJob.lastErrorCode = isConflict || permanent ? "identification_review_reconcile" : "identification_review_sync_failed"
                        try failed.save()
                    }
                } catch is HistoryProtected {
                    try Self.holdProtectedJob(job.id, container: context.container)
                    return
                }
                if isConflict || permanent, let snapshot = try? await dependencies.fetchLatest(payload.request.scanID),
                   dependencies.isWorkCurrent(lease), dependencies.ownerID() == payload.ownerID {
                    do {
                        try Self.withLegacyWrite(container: context.container, request: payload.request) { reconcile in
                            if let scan = try Self.record(payload.request.scanID, context: reconcile) {
                                var state = scan.localAIIdentificationReview
                                state.authority = snapshot.review; state.pending = nil; state.optimisticState = nil
                                state.needsAttention = false; state.conflictReconciled = true
                                scan.aiIdentificationReviewData = try state.storedData()
                                scan.userIdentificationOverride = snapshot.review_fields.user_identification_override
                                scan.userConfirmedIdentification = snapshot.review_fields.user_confirmed_identification
                                scan.confirmedSpeciesId = snapshot.review_fields.confirmed_species_id
                                scan.userReviewState = snapshot.review_fields.user_review_state
                                if scan.primaryIdentificationData != nil {
                                    let fields = snapshot.review_fields
                                    scan.confirmedSpeciesIdentityData = try ConfirmedSpeciesReview(revision: fields.confirmed_species_identity_revision,
                                        identity: fields.confirmed_species_identity, override: fields.user_identification_override,
                                        confirmed: fields.user_confirmed_identification, speciesID: fields.confirmed_species_id, state: fields.user_review_state).storedData()
                                }
                                // Drop dependent intent. Never rebase an old decision onto another device's decision.
                                let all = try dependencies.loadPendingJobs(reconcile, descriptor)
                                for dependent in all where dependent.subjectId == job.subjectId { reconcile.delete(dependent) }
                                try reconcile.save()
                            }
                        }
                    } catch is HistoryProtected {
                        try Self.holdProtectedJob(job.id, container: context.container)
                    }
                }
                return
            }
        }
    }
    private static func requireLegacy(scanID: String, context: ModelContext) throws {
        guard try !ObservationHistoryEnrollmentIntent.protects(scanID, context: context) else { throw HistoryProtected() }
    }

    private static func withLegacyWrite<Value>(container: ModelContainer, request: AIIdentificationReviewRequest,
                                               operation: (ModelContext) throws -> Value) throws -> Value {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            try requireLegacy(scanID: request.scanID, context: context)
            if let source = request.sourceScanID { try requireLegacy(scanID: source, context: context) }
            do { return try operation(context) } catch { context.rollback(); throw error }
        }
    }

    private static func holdProtectedJob(_ id: String, container: ModelContainer) throws {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            guard let job = try context.fetchOfflineJob(id: id) else { return }
            job.status = .needsAttention
            job.nextRunAt = nil
            job.lastErrorCode = "analysis_bound_review_required"
            try context.save()
        }
    }

    static func record(_ scanID: String, context: ModelContext) throws -> LocalScanRecord? {
        let uppercase = scanID.uppercased()
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanID || $0.id == uppercase })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
