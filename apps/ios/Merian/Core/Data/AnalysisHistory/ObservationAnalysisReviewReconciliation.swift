import Foundation
import SwiftData

/// Receipt recovery only. One save owns both current states, selected projection and local completion.
@MainActor
struct ObservationAnalysisReviewReconciliation {
    typealias Store = ObservationAnalysisReviewPersistence
    typealias Baseline = ObservationHistoryStateSyncService.ReviewBaseline
    let cloud: ObservationHistoryCloudClient
    var now: () -> Date = Date.init
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func reconcile(_ claim: Store.Claim, container: ModelContainer,
                   isCurrent: @escaping () -> Bool) async throws -> ObservationAnalysisReviewIntent {
        guard claim.intent.hasReceipt, !claim.intent.isComplete, isCurrent() else { throw Store.IntegrityError.unavailable }
        let owner = claim.intent.ownerID
        let lease = try cloud.begin(owner)
        defer { cloud.finish(lease) }
        let current = { isCurrent() && lease.session.userID == owner && cloud.isCurrent(lease) }
        let baseline = try checkedBaseline(claim, container: container, isCurrent: current)
        let target = try await read(claim.intent.request.analysisID, claim: claim, baseline: baseline,
                                    container: container, isCurrent: current)
        let selected: ObservationHistoryState
        if target.selectedAnalysisID == target.result.analysisID {
            selected = target
        } else {
            selected = try await read(target.selectedAnalysisID, claim: claim, baseline: baseline,
                                      container: container, isCurrent: current)
        }
        try validatePair(target: target, selected: selected, claim: claim)
        return try Store.transaction(claim.intent, container: container, isCurrent: current, save: save) { context in
            let scan = try checkedScan(claim, baseline: baseline, context: context)
            // The outgoing cache is the proof for changing selection. Updating target A
            // before applying selected C would invalidate that proof when A was selected.
            try ObservationHistoryStateSyncService.apply(selected, to: scan, baseline: baseline, context: context)
            if target.result.analysisID != selected.result.analysisID {
                _ = try ObservationHistorySyncService.insert([target.result], into: scan, ownerID: owner, context: context)
                try ObservationHistoryStateCache.admit(target, scan: scan, context: context)
            }
            return try finish(claim, context: context)
        }
    }

    private func read(_ analysis: UUID, claim: Store.Claim, baseline: Baseline, container: ModelContainer,
                      isCurrent: () -> Bool) async throws -> ObservationHistoryState {
        _ = try checkedBaseline(claim, expected: baseline, container: container, isCurrent: isCurrent)
        let date = now()
        guard ObservationAnalysisReviewIntent.validDate(date), date >= claim.startedAt, date < claim.expiresAt else {
            throw Store.IntegrityError.unavailable
        }
        let request = ObservationHistoryStateRequest(observation_id: claim.intent.request.observationID.uuidString.lowercased(),
                                                     analysis_id: analysis.uuidString.lowercased())
        let bytes = try await cloud.fetchState(request)
        try Task.checkCancellation()
        // A late reply may settle an unchanged claim. Only a new read requires unexpired work.
        _ = try checkedBaseline(claim, expected: baseline, container: container, isCurrent: isCurrent)
        return try ObservationHistoryState.decode(bytes, request: request, ownerID: claim.intent.ownerID)
    }

    private func checkedBaseline(_ claim: Store.Claim, expected: Baseline? = nil, container: ModelContainer,
                                 isCurrent: () -> Bool) throws -> Baseline {
        try Store.transaction(claim.intent, container: container, isCurrent: isCurrent) { context in
            Baseline(try checkedScan(claim, baseline: expected, context: context))
        }
    }

    private func checkedScan(_ claim: Store.Claim, baseline: Baseline?, context: ModelContext) throws -> LocalScanRecord {
        let request = claim.intent.request
        let scan = try ObservationHistorySyncService.enrolledScan(request.observationID.uuidString, context: context)
        let id = Store.jobID(request.operationID, observationID: request.observationID)
        guard let job = try context.fetchOfflineJob(id: id) else { throw Store.IntegrityError.unavailable }
        try Store.validate(claim, job: job)
        try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
        try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
        let scope = Store.observationPrefix(request.observationID)
        for sibling in try context.fetch(FetchDescriptor<OfflineJobRecord>()) where sibling.id != id && sibling.id.hasPrefix(scope) {
            guard try Store.restore(sibling).isComplete else { throw Store.IntegrityError.conflict }
        }
        if let baseline, Baseline(scan) != baseline { throw ObservationHistoryStateSyncService.AdmissionError.conflictingRevision }
        return scan
    }

    private func validatePair(target: ObservationHistoryState, selected: ObservationHistoryState, claim: Store.Claim) throws {
        guard target.ownerID == selected.ownerID, target.ownerID == claim.intent.ownerID,
              target.observationID == selected.observationID, target.observationID == claim.intent.request.observationID,
              target.result.analysisID == claim.intent.request.analysisID,
              selected.result.analysisID == target.selectedAnalysisID,
              target.selectedAnalysisID == selected.selectedAnalysisID, target.revision == selected.revision else {
            throw ObservationHistoryStateSyncService.AdmissionError.conflictingRevision
        }
        if let receipt = claim.intent.receipt, case let .applied(observationRevision, reviewRevision) = receipt.outcome {
            guard target.revision >= observationRevision, target.reviewRevision >= reviewRevision else {
                throw ObservationHistoryStateSyncService.AdmissionError.staleRevision
            }
        }
    }

    /// No standalone save: callers cannot complete a receipt without its paired projection.
    private func finish(_ claim: Store.Claim, context: ModelContext) throws -> ObservationAnalysisReviewIntent {
        let request = claim.intent.request
        guard let job = try context.fetchOfflineJob(id: Store.jobID(request.operationID, observationID: request.observationID)) else {
            throw Store.IntegrityError.unavailable
        }
        try Store.validate(claim, job: job)
        let settled = try claim.intent.reconciled(at: now())
        guard let completedAt = settled.reconciledAt, let text = String(bytes: try settled.storedData(), encoding: .utf8) else { throw Store.IntegrityError.conflict }
        job.metadataJSON = text; job.status = .complete; job.nextRunAt = nil
        job.lastErrorCode = nil; job.lastErrorMessage = nil; job.lastHTTPStatus = nil
        job.updatedAt = completedAt
        return settled
    }
}
