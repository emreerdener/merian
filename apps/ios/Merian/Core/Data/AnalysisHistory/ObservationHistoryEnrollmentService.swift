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

    /// Local admission ticket captured before an explicit caller suspends. It creates no intent.
    static func baseline(observation: UUID, container: ModelContainer) throws -> ObservationHistoryStateSyncService.ReviewBaseline {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let scan = try eligibleScan(observation, context: ModelContext(container))
            return ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: observation)
        }
    }

    @discardableResult
    func enroll(observationID: String, expectedOwnerID: UUID, container: ModelContainer,
                expectedBaseline: ObservationHistoryStateSyncService.ReviewBaseline? = nil) async throws -> UUID {
        guard let observation = UUID(uuidString: observationID) else { throw ObservationHistoryError.invalidPage }
        let lease = try cloud.begin(expectedOwnerID)
        defer { cloud.finish(lease) }
        try check(lease, owner: expectedOwnerID)
        let (baseline, intent) = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                let scan = try Self.eligibleScan(observation, context: context)
                let baseline = ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: observation)
                guard expectedBaseline == nil || expectedBaseline == baseline else { throw AdmissionError.localStateChanged }
                let intent = try ObservationHistoryEnrollmentIntent.stage(observationID: observation, ownerID: expectedOwnerID, context: context)
                try check(lease, owner: expectedOwnerID)
                try save(context)
                return (baseline, intent)
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
        let state = try ObservationHistoryState.decode(stateData, request: request, ownerID: expectedOwnerID)
        guard state.selectedAnalysisID == receipt.baselineAnalysisID, state.result.version == 3 else {
            // An idempotent enrollment replay does not reselect the baseline.
            throw AdmissionError.reconciliationRequired
        }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                try check(lease, owner: expectedOwnerID)
                let scan = try Self.eligibleScan(observation, context: context)
                guard ObservationHistoryStateSyncService.ReviewBaseline(scan, displayAnalysisID: observation) == baseline else {
                    throw AdmissionError.localStateChanged
                }
                try ObservationHistoryStateSyncService.validateAuthority(state.review, against: scan)
                guard ObservationHistoryStateSyncService.matches(state.review, scan: scan),
                      let display = try SavedIdentificationDisplayBaseline.capture(
                        AnalysisDisplaySnapshot(analysisID: receipt.baselineAnalysisID, record: scan), matching: state.result) else {
                    throw AdmissionError.reconciliationRequired
                }
                _ = try ObservationHistorySyncService.insert([state.result], into: scan, ownerID: expectedOwnerID, context: context)
                _ = try ObservationHistoryStateCache.admit(state, scan: scan, context: context, initialSavedDisplay: display)
                scan.analysisOwnerAccountID = expectedOwnerID.uuidString.lowercased()
                scan.selectedAnalysisID = receipt.baselineAnalysisID.uuidString.lowercased()
                scan.observationStateRevision = state.revision
                try check(lease, owner: expectedOwnerID)
                try ObservationHistoryEnrollmentIntent.acknowledge(intent, context: context)
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
