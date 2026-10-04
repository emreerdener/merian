import Foundation
import SwiftData

/// A server-ordered page index followed by bounded exact child lookups. Never
/// enumerates the cascade array or treats a partial cache as complete history.
@MainActor
struct ObservationHistoryListingService {
    struct Context: Equatable {
        let owner: UUID
        let selected: UUID
        let revision: Int
        let pendingOperation: UUID?
        let undoOperation: UUID?
    }
    struct Entry {
        let result: ObservationHistoryPage.Result
        let display: AnalysisDisplaySnapshot?
        let authority: ObservationHistoryAuthority?
    }
    struct Page {
        let entries: [Entry]
        let nextBeforeOrdinal: Int?
        let context: Context
    }
    var cloud = ObservationHistoryCloudClient.live

    func context(observationID: String, container: ModelContainer) throws -> Context {
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
            let owner = try ObservationHistoryPage.uuid(scan.analysisOwnerAccountID)
            let lease = try cloud.begin(owner)
            defer { cloud.finish(lease) }
            guard lease.session.userID == owner, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let selected = try ObservationHistoryPage.uuid(scan.selectedAnalysisID)
            let revision = try ObservationHistoryPage.integer(scan.observationStateRevision)
            guard revision > 0 else { throw ObservationHistoryError.invalidPage }
            let intent = try ObservationHistorySelectionIntent.load(scan.id, context: context)
            guard intent == nil || intent?.owner == owner.uuidString.lowercased() else { throw ObservationHistoryError.accountChanged }
            let pending = intent.flatMap { $0.receipt == nil && $0.rejection == nil ? UUID(uuidString: $0.request.operation_id) : nil }
            let undo = intent?.receipt.flatMap { receipt -> UUID? in
                guard receipt.selected_analysis_id == selected.uuidString.lowercased(), receipt.observation_revision == revision else { return nil }
                return UUID(uuidString: receipt.operation_id)
            }
            return Context(owner: owner, selected: selected, revision: revision, pendingOperation: pending, undoOperation: undo)
        }
    }

    func hasMultiple(observationID: String, container: ModelContainer) throws -> Bool {
        let baseline = try context(observationID: observationID, container: container)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
            let observation = scan.id, owner = baseline.owner.uuidString.lowercased()
            var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.observationID == observation && $0.ownerAccountID == owner })
            query.fetchLimit = 2
            return try context.fetch(query).count == 2
        }
    }

    func page(observationID: String, beforeOrdinal: Int? = nil, container: ModelContainer) async throws -> Page {
        let baseline = try context(observationID: observationID, container: container)
        let receipt = try await ObservationHistorySyncService(cloud: cloud).syncPage(
            observationID: observationID, beforeOrdinal: beforeOrdinal, limit: 20, container: container)
        try Task.checkCancellation()
        let current = try context(observationID: observationID, container: container)
        guard current == baseline, receipt.stateRevision == current.revision else { throw ObservationHistoryPreviewService.AdmissionError.refreshRequired }
        let entries = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
            return try receipt.analysisIDs.map { try Self.entry($0, scan: scan, context: context) }
        }
        return Page(entries: entries, nextBeforeOrdinal: receipt.nextBeforeOrdinal, context: current)
    }

    /// Read only. Cached authority is usable for preparation only at the current
    /// acknowledged revision; server CAS still decides whether a request applies.
    func cached(observationID: String, analysisID: UUID, container: ModelContainer) throws -> Entry {
        _ = try context(observationID: observationID, container: container)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            return try Self.entry(analysisID, scan: ObservationHistorySyncService.enrolledScan(observationID, context: context), context: context)
        }
    }

    private static func entry(_ analysisID: UUID, scan: LocalScanRecord, context: ModelContext) throws -> Entry {
        let id = analysisID.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let stored = try context.fetch(query).first, stored.ownerAccountID == scan.analysisOwnerAccountID,
              stored.observationID == scan.id, stored.resultSnapshotData.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ObservationHistoryError.unavailable }
        let envelope = try JSONSerialization.jsonObject(with: stored.resultSnapshotData) as? [String: Any]
        let result = try ObservationHistoryPage.snapshot(stored.resultSnapshotData, observationID: scan.id.lowercased(), ordinal: ObservationHistoryPage.integer(envelope?["ordinal"]))
        guard result.analysisID == analysisID, result.version == stored.snapshotVersion, result.completedAt == stored.completedAt else { throw ObservationHistoryError.resultConflict }
        var display = try ObservationHistoryDisplayProjection.snapshot(result).map { try AnalysisDisplaySnapshot.restore($0, analysisID: analysisID) }
        var authority: ObservationHistoryAuthority?
        if let state = stored.state {
            guard state.id == id, state.ownerAccountID == stored.ownerAccountID, state.observationID == scan.id else { throw ObservationHistoryError.resultConflict }
            if let saved = state.displaySnapshotData { display = try ObservationHistoryDisplayProjection.restore(saved, matching: result) }
            if state.observationStateRevision == scan.observationStateRevision {
                guard state.reviewRevision >= 0, state.reviewRevision <= state.observationStateRevision,
                      state.reviewSnapshotData.count <= 32_768 else { throw ObservationHistoryError.resultConflict }
                authority = try ObservationHistoryAuthority.decode(JSONSerialization.jsonObject(with: state.reviewSnapshotData))
            }
        }
        return Entry(result: result, display: display, authority: authority)
    }
}
