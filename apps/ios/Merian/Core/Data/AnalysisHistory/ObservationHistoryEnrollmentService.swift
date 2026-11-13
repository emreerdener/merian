import Foundation
import SwiftData

/// Prepared enrollment only. No scheduler, migration, or UI invokes this owner.
@MainActor
struct ObservationHistoryEnrollmentService {
    enum AdmissionError: Error, Equatable {
        case pendingWork, reconciliationRequired, localStateChanged
    }

    var cloud = ObservationHistoryCloudClient.live
    var save: (ModelContext) throws -> Void = { try $0.save() }

    /// Scan-only mutations must not compete with staged or acknowledged history.
    /// A fresh locked read also observes holds committed by another context.
    static func permitsLegacyMutation(scanID: String, container: ModelContainer?) -> Bool {
        guard let container else { return false }
        do {
            return try ConfirmedSpeciesReviewPersistence.transaction {
                let context = ModelContext(container)
                let lower = scanID.lowercased(), upper = scanID.uppercased()
                var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
                query.fetchLimit = 2
                guard try context.fetch(query).count == 1 else { return false }
                return try !ObservationHistoryEnrollmentIntent.protects(scanID, context: context)
            }
        } catch { return false }
    }

    /// Local admission ticket captured before an explicit caller suspends. It creates no intent.
    static func baseline(observation: UUID, container: ModelContainer) throws -> ObservationHistoryStateSyncService.ReviewBaseline {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let scan = try eligibleScan(observation, context: ModelContext(container))
            return ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: observation)
        }
    }

    static func ordinaryCompletionAdmission(observation: UUID, owner: UUID, container: ModelContainer) throws -> OrdinaryInferenceCompletion.Proof? {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try eligibleScan(observation, context: context)
            return try OrdinaryInferenceCompletion.retained(for: scan, owner: owner, context: context)
        }
    }

    static func nativeRecoveryAdmission(_ candidate: SharedMediaNativeReceivedCandidate,
                                        container: ModelContainer) throws -> NativeInitialEnrollmentRecovery? {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container); context.autosaveEnabled = false
            guard let proof = try SharedMediaNativePhotoAllocationSnapshot.enrollmentRecovery(candidate, context: context) else { return nil }
            _ = try eligibleScan(proof.intent.observationID, context: context)
            return proof
        }
    }

    /// Explicit metadata-only discovery remains available while an exact active
    /// enrollment holds native media audits. Never returns media/save authority.
    static func nativeRecoveryPage(ownerID: UUID, container: ModelContainer,
                                   cursor: SharedMediaNativeInitialPage.Cursor?) throws -> SharedMediaNativeInitialPage {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container); context.autosaveEnabled = false
            let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>())
            let profile = try SharedMediaNativeAppEligibility.profile(inventory)
            guard profile.ownerID == ownerID else { throw SharedMediaStorageFailure.stale }
            let header = try SharedMediaNativeInitialPage.header(context, profile: profile)
            let after = try SharedMediaNativeInitialPage.lower(cursor, kind: .enrollment, profile: profile, header: header)
            let prefix = ObservationHistoryEnrollmentIntent.prefix
            // The ASCII colon namespace occupies [prefix, nextNamespace).
            // SwiftData does not translate String.hasPrefix in predicates.
            guard prefix.last == ":" else { throw SharedMediaStorageFailure.conflict }
            let nextNamespace = String(prefix.dropLast()) + ";"
            var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id >= prefix && $0.id < nextNamespace && $0.id > after },
                sortBy: [SortDescriptor(\.id, comparator: .lexical)])
            query.fetchLimit = SharedMediaStoragePolicy.pageSize
            let jobs = try context.fetch(query)
            var candidates: [SharedMediaNativeReceivedCandidate] = []
            for job in jobs {
                try Task.checkCancellation()
                guard let observation = UUID(uuidString: String(job.id.dropFirst(prefix.count))),
                      job.id == prefix + observation.uuidString.lowercased() else { throw ObservationHistoryEnrollmentIntent.IntegrityError.invalidIntent }
                if job.statusRaw == OfflineJobStatus.cancelled.rawValue, job.metadataJSON == nil,
                   job.kindRaw == OfflineJobKind.future.rawValue, job.subjectId == observation.uuidString.lowercased() { continue }
                guard let intent = try ObservationHistoryEnrollmentIntent.existing(observationID: observation, ownerID: ownerID, context: context) else {
                    throw ObservationHistoryEnrollmentIntent.IntegrityError.invalidIntent
                }
                let lower = observation.uuidString.lowercased(), upper = observation.uuidString
                let scan = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
                let authority = try SharedMediaConsumerAuthority.classify(raw: scan.mediaAuthorityRaw, consumerID: scan.sharedMediaConsumerID, record: .scan)
                guard case .nativeInitial(let binding) = authority else {
                    guard authority == .legacy || authority == .historyProjection else { throw SharedMediaStorageFailure.conflict }
                    continue
                }
                guard let consumer = try SharedMediaConsumerLookup.one(context, id: binding),
                      let row = try SharedMediaNativeReceivingPhaseGraph.row(consumer.packageID, in: context) else {
                    throw SharedMediaStorageFailure.conflict
                }
                let candidate = try SharedMediaNativeInitialPage.candidate(.init(row), profile: profile)
                guard let proof = try SharedMediaNativePhotoAllocationSnapshot.enrollmentRecovery(candidate, context: context),
                      proof.intent == intent else { throw SharedMediaStorageFailure.conflict }
                _ = try eligibleScan(observation, context: context)
                candidates.append(candidate)
            }
            guard try SharedMediaNativeInitialPage.header(ModelContext(container), profile: profile) == header else {
                throw SharedMediaStorageFailure.stale
            }
            return .init(candidates: candidates, next: jobs.count == SharedMediaStoragePolicy.pageSize
                ? jobs.last.map { .init(kind: .enrollment, profile: profile, header: header, after: $0.id) } : nil)
        }
    }

    private static func requireRecovery(_ proof: NativeInitialEnrollmentRecovery?, observation: UUID, owner: UUID,
                                        context: ModelContext) throws {
        guard let proof else { return }
        guard proof.intent.observationID == observation, proof.intent.ownerID == owner,
              try SharedMediaNativePhotoAllocationSnapshot.enrollmentRecovery(proof.candidate, context: context) == proof else {
            throw AdmissionError.localStateChanged
        }
    }

    /// Only the native application's exact retained receipt and this active intent can
    /// establish pristine review authority. Legacy rows and already-enrolled rows
    /// never acquire authority through this path.
    private static func nativeFirstImport(_ scan: LocalScanRecord, intent: ObservationHistoryEnrollmentIntent.Receipt,
                                          context: ModelContext) throws -> NativeInitialEnrollmentRecovery? {
        guard case let .nativeInitial(binding) = try SharedMediaConsumerAuthority.classify(
            raw: scan.mediaAuthorityRaw, consumerID: scan.sharedMediaConsumerID, record: .scan) else { return nil }
        guard let consumer = try SharedMediaConsumerLookup.one(context, id: binding),
              let row = try SharedMediaNativeReceivingPhaseGraph.row(consumer.packageID, in: context) else {
            throw AdmissionError.localStateChanged
        }
        let inventoryID = consumer.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let candidate = try SharedMediaNativeInitialPage.candidate(.init(row), profile: SharedMediaNativeAppEligibility.profile(inventory))
        guard let proof = try SharedMediaNativePhotoAllocationSnapshot.enrollmentRecovery(candidate, context: context),
              proof.intent == intent, proof.prepared.bindingID == binding,
              proof.prepared.observationID.uuidString.lowercased() == scan.id else { throw AdmissionError.localStateChanged }
        return proof
    }

    @discardableResult
    func enroll(observationID: String, expectedOwnerID: UUID, container: ModelContainer,
                expectedBaseline: ObservationHistoryStateSyncService.ReviewBaseline? = nil,
                recovery: NativeInitialEnrollmentRecovery? = nil) async throws -> UUID {
        guard let observation = UUID(uuidString: observationID) else { throw ObservationHistoryError.invalidPage }
        let lease = try cloud.begin(expectedOwnerID)
        defer { cloud.finish(lease) }
        try check(lease, owner: expectedOwnerID)
        let (baseline, intent, native, ordinary) = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                try Self.requireRecovery(recovery, observation: observation, owner: expectedOwnerID, context: context)
                let scan = try Self.eligibleScan(observation, context: context)
                let baseline = ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: observation)
                guard expectedBaseline == nil || expectedBaseline == baseline else { throw AdmissionError.localStateChanged }
                let ordinary = try OrdinaryInferenceCompletion.retained(for: scan, owner: expectedOwnerID, context: context)
                let intent = try recovery?.intent ?? ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: expectedOwnerID, context: context)
                try check(lease, owner: expectedOwnerID)
                try save(context)
                return (baseline, intent, try Self.nativeFirstImport(scan, intent: intent, context: context), ordinary)
            } catch { context.rollback(); throw error }
        }
        // The durable hold survives every ambiguous outcome after this point.
        try check(lease, owner: expectedOwnerID)
        let data = try await cloud.enroll(observation)
        try check(lease, owner: expectedOwnerID)
        let receipt = try ObservationHistoryEnrollment.decode(data, observationID: observation, ownerID: expectedOwnerID)
        let request = ObservationHistoryStateRequest(observation_id: observation.uuidString.lowercased(), analysis_id: nil)
        let stateData = try await cloud.fetchState(request)
        try check(lease, owner: expectedOwnerID)
        var state = try ObservationHistoryState.decode(stateData, request: request, ownerID: expectedOwnerID)
        var original = state
        if state.selectedAnalysisID != receipt.baselineAnalysisID {
            // Never join separate network snapshots or reselect A over B. The
            // additional read returns both states under one server observation fence.
            let pairData = try await cloud.reconcileEnrollment(observation)
            try check(lease, owner: expectedOwnerID)
            let pair = try ObservationHistoryEnrollmentSelection.decode(pairData, observation: observation, owner: expectedOwnerID, receipt: receipt)
            original = pair.baseline; state = pair.selected
        }
        guard original.result.analysisID == receipt.baselineAnalysisID, original.result.version == 3 else { throw AdmissionError.reconciliationRequired }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                try check(lease, owner: expectedOwnerID)
                try Self.requireRecovery(recovery, observation: observation, owner: expectedOwnerID, context: context)
                let scan = try Self.eligibleScan(observation, context: context)
                guard ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: observation) == baseline,
                      try Self.nativeFirstImport(scan, intent: intent, context: context) == native,
                      try OrdinaryInferenceCompletion.retained(for: scan, owner: expectedOwnerID, context: context) == ordinary else {
                    throw AdmissionError.localStateChanged
                }
                try ObservationHistoryStateSyncService.validateAuthority(original.review, against: scan)
                guard ObservationHistoryStateSyncService.matches(original.review, scan: scan) else {
                    throw AdmissionError.reconciliationRequired
                }
                let projection = AnalysisDisplaySnapshot(analysisID: receipt.baselineAnalysisID, record: scan)
                let strictDisplay = try SavedIdentificationDisplayBaseline.capture(projection, matching: original.result)
                let originalDisplay = try strictDisplay == nil ? ordinary.flatMap {
                    try SavedIdentificationDisplayBaseline.captureOrdinary(projection, matching: original.result, proof: $0, owner: expectedOwnerID)
                } : nil
                guard let display = strictDisplay ?? originalDisplay else { throw AdmissionError.reconciliationRequired }
                let changesSelection = state.selectedAnalysisID != receipt.baselineAnalysisID
                let results = changesSelection ? [original.result, state.result] : [original.result]
                _ = try ObservationHistorySyncService.insert(results, into: scan, ownerID: expectedOwnerID, context: context)
                _ = try ObservationHistoryStateCache.admit(original, scan: scan, context: context, initialSavedDisplay: display)
                if changesSelection {
                    // First enrollment has its own unchanged legacy/intent proof;
                    // ordinary selected-state/Undo admission remains untouched.
                    try ObservationHistoryStateSyncService.requireRepresentableAuthority(state.review)
                    guard let selectedDisplay = try ObservationHistoryStateCache.admit(state, scan: scan, context: context) else {
                        throw AdmissionError.reconciliationRequired
                    }
                    selectedDisplay.apply(to: scan)
                    try ObservationHistoryStateSyncService.applyAdmittedAuthority(state, to: scan)
                } else if (native != nil && baseline.isPristineNativeReview) || ordinary != nil,
                          original.reviewRevision == 0,
                          original.review.identityRevision == 0, original.review.aiReview == nil,
                          original.review.speciesReview == nil, original.review.confirmed == false,
                          original.review.state == .unreviewed {
                    // Preserve the pristine visible fields. The authenticated representation
                    // records a revision-zero clear, never a confirmed species or user action.
                    try ObservationHistoryStateSyncService.acknowledgePristineReview(original, scan: scan)
                }
                scan.analysisOwnerAccountID = expectedOwnerID.uuidString.lowercased()
                scan.selectedAnalysisID = state.selectedAnalysisID.uuidString.lowercased()
                scan.observationStateRevision = state.revision
                try check(lease, owner: expectedOwnerID)
                try ObservationHistoryEnrollmentIntent.acknowledge(intent, enrollment: receipt, result: original.result, context: context)
                try save(context)
                return receipt.baselineAnalysisID
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func check(_ lease: AccountBoundWorkLease, owner: UUID) throws {
        try Task.checkCancellation()
        guard lease.session.userID == owner, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
    }

    struct BaselineRecoveryAdmission: Equatable {
        let display: ObservationHistoryStateSyncService.ReviewBaseline
        let analysisID: UUID
        let bytes: Data
    }

    static func requiresBaselineRecovery(observation: UUID, owner: UUID, container: ModelContainer) throws -> Bool {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container), lower = observation.uuidString.lowercased(), upper = observation.uuidString
            var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
            query.fetchLimit = 2
            let rows = try context.fetch(query)
            guard rows.count == 1, let scan = rows.first, scan.id == lower else { throw ObservationHistoryError.deleted }
            if scan.analysisOwnerAccountID == nil && scan.selectedAnalysisID == nil && scan.observationStateRevision == nil { return false }
            _ = try baselineRecoveryAdmission(observation: observation, owner: owner, context: context)
            return true
        }
    }

    static func baselineRecoveryAdmission(observation: UUID, owner: UUID, container: ModelContainer) throws -> BaselineRecoveryAdmission {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try baselineRecoveryAdmission(observation: observation, owner: owner, context: ModelContext(container))
        }
    }

    private static func baselineRecoveryAdmission(observation: UUID, owner: UUID, context: ModelContext) throws -> BaselineRecoveryAdmission {
        let lower = observation.uuidString.lowercased(), upper = observation.uuidString
        let scan = try ObservationHistorySyncService.enrolledScan(lower, context: context)
        guard scan.id == lower, scan.analysisOwnerAccountID == owner.uuidString.lowercased(),
              try !ObservationHistoryEnrollmentIntent.holds(lower, context: context) else { throw AdmissionError.localStateChanged }
        try ObservationHistorySelectionIntent.requireIdle(lower, context: context)
        try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
        try ObservationHistoryStateSyncService.requireSettledAnalysisReview(scan, context: context)
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate {
            ($0.observationID == lower || $0.observationID == upper) && $0.snapshotVersion == 3
        })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let child = rows.first, child.observationID == lower,
              child.ownerAccountID == owner.uuidString.lowercased(), child.completedAt == nil else { throw AdmissionError.reconciliationRequired }
        let result = try ObservationHistoryPage.snapshot(child.resultSnapshotData, observationID: lower, ordinal: 1)
        guard result.version == 3, child.id == result.analysisID.uuidString.lowercased() else { throw AdmissionError.reconciliationRequired }
        // Validate any existing metadata before network dispatch; corruption is not absence.
        if let association = try ObservationHistoryEnrollmentIntent.baseline(observationID: observation, ownerID: owner, context: context) {
            guard association.baselineAnalysisID == result.analysisID,
                  association.snapshotSHA256 == ObservationHistoryEnrollmentIntent.baselineDigest(result.bytes) else {
                throw AdmissionError.reconciliationRequired
            }
        }
        return .init(display: .init(scan, displayAnalysisID: observation), analysisID: result.analysisID, bytes: result.bytes)
    }

    /// Adds only recovered provenance for an already imported exact local V3 baseline.
    /// Selection, review, display, media and active enrollment state are never written.
    func recoverBaseline(observation: UUID, owner: UUID, container: ModelContainer,
                         expected: BaselineRecoveryAdmission) async throws -> UUID {
        let lease = try cloud.begin(owner)
        defer { cloud.finish(lease) }
        try check(lease, owner: owner)
        guard try Self.baselineRecoveryAdmission(observation: observation, owner: owner, container: container) == expected else {
            throw AdmissionError.localStateChanged
        }
        let data = try await cloud.recoverBaseline(observation)
        try check(lease, owner: owner)
        let recovered = try ObservationHistoryBaselineRecovery.decode(data, observationID: observation, ownerID: owner)
        guard recovered.result.analysisID == expected.analysisID, recovered.result.bytes == expected.bytes else {
            throw AdmissionError.reconciliationRequired
        }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                try check(lease, owner: owner)
                guard try Self.baselineRecoveryAdmission(observation: observation, owner: owner, context: context) == expected else {
                    throw AdmissionError.localStateChanged
                }
                try ObservationHistoryEnrollmentIntent.recoverBaseline(recovered, observationID: observation, ownerID: owner, context: context)
                try check(lease, owner: owner)
                if context.hasChanges { try save(context) }
                return recovered.result.analysisID
            } catch { context.rollback(); throw error }
        }
    }

    private static func eligibleScan(_ observation: UUID, context: ModelContext) throws -> LocalScanRecord {
        let lower = observation.uuidString.lowercased(), upper = observation.uuidString
        var deletions = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })
        deletions.fetchLimit = 1
        guard try context.fetch(deletions).isEmpty else { throw ObservationHistoryError.deleted }
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        let scans = try context.fetch(query)
        guard scans.count == 1, let scan = scans.first else { throw ObservationHistoryError.deleted }
        guard scan.analysisOwnerAccountID == nil, scan.selectedAnalysisID == nil,
              scan.observationStateRevision == nil, scan.analysisSelectionInitialized else { throw ObservationHistoryError.unavailable }
        var results = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.observationID == lower || $0.observationID == upper })
        results.fetchLimit = 1
        var states = FetchDescriptor<LocalAnalysisStateRecord>(predicate: #Predicate { $0.observationID == lower || $0.observationID == upper })
        states.fetchLimit = 1
        guard try context.fetch(results).isEmpty, try context.fetch(states).isEmpty else { throw ObservationHistoryError.resultConflict }
        var queued = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        queued.fetchLimit = 1
        let kind = OfflineJobKind.scanIngestion.rawValue
        let complete = OfflineJobStatus.complete.rawValue, cancelled = OfflineJobStatus.cancelled.rawValue
        var jobs = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.kindRaw == kind && ($0.subjectId == lower || $0.subjectId == upper) &&
                $0.statusRaw != complete && $0.statusRaw != cancelled
        })
        jobs.fetchLimit = 1
        guard try context.fetch(queued).isEmpty, try context.fetch(jobs).isEmpty else { throw AdmissionError.pendingWork }
        try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
        return scan
    }
}
