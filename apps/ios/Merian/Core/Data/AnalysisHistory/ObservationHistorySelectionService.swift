import Foundation
import SwiftData

/// Prepared explicit request owner. Staging changes no visible identification;
/// an acknowledged receipt plus a current state read commit together. Only the
/// injected history UI is prepared; ordinary callers and server gates stay closed.
@MainActor
struct ObservationHistorySelectionService {
    typealias Intent = ObservationHistorySelectionIntent
    typealias Sync = ObservationHistoryStateSyncService
    var cloud = ObservationHistoryCloudClient.live
    var save: (ModelContext) throws -> Void = { try $0.save() }

    @discardableResult
    func prepare(observationID: String, analysisID: UUID, ownerID: UUID, container: ModelContainer) throws -> ObservationHistorySelectionRequest {
        try stage(observationID: observationID, target: analysisID, ownerID: ownerID, container: container)
    }

    @discardableResult
    func prepareUndo(observationID: String, operationID: UUID, ownerID: UUID, container: ModelContainer) throws -> ObservationHistorySelectionRequest {
        try stage(observationID: observationID, target: nil, undoOperation: operationID, ownerID: ownerID, container: container)
    }

    private func stage(observationID: String, target: UUID?, undoOperation: UUID? = nil, ownerID: UUID, container: ModelContainer) throws -> ObservationHistorySelectionRequest {
        let lease = try cloud.begin(ownerID)
        defer { cloud.finish(lease) }
        try check(lease, owner: ownerID)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                let scan = try eligible(observationID, owner: ownerID, context: context)
                try Intent.requireIdle(scan.id, context: context)
                let prior = try Intent.load(scan.id, context: context)
                if let prior, prior.owner != ownerID.uuidString.lowercased() { throw ObservationHistoryError.accountChanged }
                let previous = try ObservationHistoryPage.uuid(scan.selectedAnalysisID)
                let revision = try ObservationHistoryPage.integer(scan.observationStateRevision)
                let previousCache = try ObservationHistorySelectionProjection.retained(previous, scan: scan, context: context)
                let analysis: UUID
                let undoReview: Int?
                if let target { analysis = target; undoReview = nil } else {
                    guard let prior, let receipt = prior.receipt,
                          receipt.operation_id == undoOperation?.uuidString.lowercased(),
                          receipt.observation_revision == revision, receipt.selected_analysis_id == previous.uuidString.lowercased() else {
                        throw Intent.Failure.staleUndo
                    }
                    analysis = try ObservationHistoryPage.uuid(prior.previous)
                    undoReview = prior.previousReview
                }
                guard analysis != previous, analysis != UUID(uuidString: scan.id) else { throw ObservationHistoryError.invalidPage }
                let targetCache = try ObservationHistorySelectionProjection.retained(analysis, scan: scan, context: context)
                guard [1, 2, 3].contains(targetCache.snapshotVersion), [1, 2, 3].contains(previousCache.snapshotVersion) else {
                    throw ObservationHistoryError.unavailable
                }
                if let undoReview {
                    guard targetCache.reviewRevision == undoReview else { throw Intent.Failure.staleUndo }
                } else {
                    guard targetCache.observationRevision == revision else { throw Sync.AdmissionError.staleRevision }
                }
                try Sync.requireRepresentableAuthority(targetCache.authority)
                let request = ObservationHistorySelectionRequest(observation: try ObservationHistoryPage.uuid(scan.id.lowercased()),
                    analysis: analysis, revision: revision, review: targetCache.reviewRevision)
                try request.validate()
                let entry = Intent.Entry(version: 1, owner: ownerID.uuidString.lowercased(), previous: previous.uuidString.lowercased(),
                    previousReview: previousCache.reviewRevision, request: request)
                try Intent.store(entry, context: context)
                try check(lease, owner: ownerID)
                try save(context)
                return request
            } catch { context.rollback(); throw error }
        }
    }

    @discardableResult
    func sendPending(observationID: String, container: ModelContainer) async throws -> ObservationHistorySelectionOutcome {
        let entry = try ConfirmedSpeciesReviewPersistence.transaction {
            guard let entry = try Intent.load(observationID, context: ModelContext(container)), entry.receipt == nil, entry.rejection == nil else {
                throw Intent.Failure.invalidIntent
            }
            return entry
        }
        let owner = try ObservationHistoryPage.uuid(entry.owner)
        let lease = try cloud.begin(owner)
        defer { cloud.finish(lease) }
        try check(lease, owner: owner)
        let baseline = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            return try Sync.ReviewBaseline(pendingScan(entry, context: context))
        }
        let data = try await cloud.select(entry.request)
        try check(lease, owner: owner)
        let outcome = try ObservationHistorySelectionOutcome.decode(data, request: entry.request, previous: entry.previous)
        let request = ObservationHistoryStateRequest(observation_id: entry.request.observation_id, analysis_id: nil)
        let stateData = try await cloud.fetchState(request)
        try check(lease, owner: owner)
        let state = try ObservationHistoryState.decode(stateData, request: request, ownerID: owner)
        if case let .selected(receipt) = outcome {
            guard state.revision >= receipt.observation_revision else { throw Sync.AdmissionError.staleRevision }
            if state.revision == receipt.observation_revision {
                guard state.selectedAnalysisID.uuidString.lowercased() == receipt.selected_analysis_id,
                      state.reviewRevision == receipt.review_revision else { throw Sync.AdmissionError.conflictingRevision }
            }
        }
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                try check(lease, owner: owner)
                let scan = try pendingScan(entry, context: context)
                guard Sync.ReviewBaseline(scan) == baseline else { throw Sync.AdmissionError.conflictingRevision }
                try Sync.apply(state, to: scan, baseline: baseline, context: context)
                var completed = entry
                switch outcome {
                case let .selected(receipt): completed.receipt = receipt
                case let .rejected(rejection):
                    completed = Intent.Entry(version: 2, owner: entry.owner, previous: entry.previous,
                        previousReview: entry.previousReview, request: entry.request, rejection: rejection)
                }
                try Intent.store(completed, context: context)
                try check(lease, owner: owner)
                try save(context)
                return outcome
            } catch { context.rollback(); throw error }
        }
    }

    private func eligible(_ observation: String, owner: UUID, context: ModelContext) throws -> LocalScanRecord {
        let scan = try ObservationHistorySyncService.enrolledScan(observation, context: context)
        guard scan.analysisOwnerAccountID == owner.uuidString.lowercased() else { throw ObservationHistoryError.accountChanged }
        try Sync.requireSettledReview(scan, context: context)
        let authority = try ObservationHistorySelectionProjection.retainedAuthority(scan: scan, context: context)
        guard scan.localAIIdentificationReview.authority != nil || scan.confirmedSpeciesIdentityData != nil,
              Sync.matches(authority, scan: scan) else { throw Sync.AdmissionError.pendingReview }
        return scan
    }

    private func pendingScan(_ entry: Intent.Entry, context: ModelContext) throws -> LocalScanRecord {
        guard try Intent.load(entry.request.observation_id, context: context) == entry else { throw Intent.Failure.invalidIntent }
        let scan = try eligible(entry.request.observation_id, owner: ObservationHistoryPage.uuid(entry.owner), context: context)
        guard scan.selectedAnalysisID == entry.previous, scan.observationStateRevision == entry.request.expected_observation_revision else {
            throw Sync.AdmissionError.conflictingRevision
        }
        let target = try ObservationHistorySelectionProjection.retained(ObservationHistoryPage.uuid(entry.request.analysis_id), scan: scan, context: context)
        let previous = try ObservationHistorySelectionProjection.retained(ObservationHistoryPage.uuid(entry.previous), scan: scan, context: context)
        guard [1, 2, 3].contains(target.snapshotVersion), [1, 2, 3].contains(previous.snapshotVersion) else { throw ObservationHistoryError.unavailable }
        guard target.reviewRevision == entry.request.expected_review_revision else { throw Sync.AdmissionError.conflictingRevision }
        try Sync.requireRepresentableAuthority(target.authority)
        return scan
    }

    private func check(_ lease: AccountBoundWorkLease, owner: UUID) throws {
        try Task.checkCancellation()
        guard lease.session.userID == owner, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
    }
}
