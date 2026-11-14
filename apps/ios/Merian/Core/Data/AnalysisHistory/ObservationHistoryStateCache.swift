import Foundation
import SwiftData

/// Caller owns the account/deletion/revision fences, rollback, and atomic save.
@MainActor
enum ObservationHistoryStateCache {
    @discardableResult
    static func admit(_ state: ObservationHistoryState, scan: LocalScanRecord, context: ModelContext, initialSavedDisplay: Data? = nil) throws -> AnalysisDisplaySnapshot? {
        let id = state.result.analysisID.uuidString.lowercased()
        var results = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
        results.fetchLimit = 1
        guard let result = try context.fetch(results).first,
              result.ownerAccountID == state.ownerID.uuidString.lowercased(), result.observationID == scan.id,
              result.resultSnapshotData == state.result.bytes else { throw ObservationHistoryError.resultConflict }
        var states = FetchDescriptor<LocalAnalysisStateRecord>(predicate: #Predicate { $0.id == id })
        states.fetchLimit = 1
        let existing = try context.fetch(states).first
        let display: Data?
        let preview: AnalysisDisplaySnapshot?
        if state.result.version == 3 {
            // One-time local capture. Later enrichment never replaces this baseline.
            display = existing?.displaySnapshotData ?? initialSavedDisplay
            preview = try display.map { try ObservationHistoryDisplayProjection.restore($0, matching: state.result) }
        } else {
            guard initialSavedDisplay == nil else { throw ObservationHistoryError.resultConflict }
            if let saved = existing?.displaySnapshotData {
                preview = try ObservationHistoryDisplayProjection.restore(saved, matching: state.result)
                display = saved // Preserve immutable cache bytes after validating equivalent nested encoding.
            } else {
                display = try ObservationHistoryDisplayProjection.snapshot(state.result)
                preview = try display.map { try AnalysisDisplaySnapshot.restore($0, analysisID: state.result.analysisID) }
            }
        }
        if let saved = existing {
            guard saved.ownerAccountID == result.ownerAccountID, saved.observationID == result.observationID,
                  result.state?.persistentModelID == saved.persistentModelID else { throw ObservationHistoryError.resultConflict }
            try validateAuthority(state.review, after: ObservationHistoryAuthority.decode(JSONSerialization.jsonObject(with: saved.reviewSnapshotData)))
            try saved.update(observationStateRevision: state.revision, reviewRevision: state.reviewRevision,
                reviewSnapshotData: state.review.data, displaySnapshotData: display)
        } else {
            guard result.state == nil else { throw ObservationHistoryError.resultConflict }
            let saved = try LocalAnalysisStateRecord(analysisID: state.result.analysisID, observationID: scan.id,
                ownerAccountID: state.ownerID, observationStateRevision: state.revision, reviewRevision: state.reviewRevision,
                reviewSnapshotData: state.review.data, displaySnapshotData: display)
            context.insert(saved)
            result.state = saved
        }
        return preview
    }

    /// Nested review revisions belong to this analysis, never the old selection.
    private static func validateAuthority(_ incoming: ObservationHistoryAuthority, after previous: ObservationHistoryAuthority) throws {
        guard incoming.identityRevision >= previous.identityRevision else { throw LocalAnalysisStateRecord.StorageError.staleRevision }
        if incoming.identityRevision == previous.identityRevision {
            guard incoming.speciesReview == previous.speciesReview,
                  incoming.confirmedSpeciesID == previous.confirmedSpeciesID,
                  incoming.override == previous.override,
                  (incoming.confirmed ?? false) == (previous.confirmed ?? false),
                  (incoming.state ?? .unreviewed) == (previous.state ?? .unreviewed) else {
                throw LocalAnalysisStateRecord.StorageError.conflictingRevision
            }
        }
        if let old = previous.aiReview {
            guard let new = incoming.aiReview, new.revision >= old.revision else { throw LocalAnalysisStateRecord.StorageError.staleRevision }
            guard new.revision != old.revision || new == old else { throw LocalAnalysisStateRecord.StorageError.conflictingRevision }
        }
    }
}
