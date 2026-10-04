import Foundation
import SwiftData

/// Explicit owner preview only. Never selects, refreshes the current projection,
/// settles pending review, awards credit, or supplies a Restore receipt.
@MainActor
struct ObservationHistoryPreviewService {
    enum AdmissionError: Error, Equatable {
        case staleRevision, refreshRequired, conflictingRevision
    }

    enum DisplayOrigin: Equatable { case analysisResult, savedLocalProjection }

    struct Preview {
        let state: ObservationHistoryState
        let display: AnalysisDisplaySnapshot?
        var displayOrigin: DisplayOrigin? {
            guard display != nil else { return nil }
            return state.result.version == 3 ? .savedLocalProjection : .analysisResult
        }
        var isSelected: Bool { state.selectedAnalysisID == state.result.analysisID }
    }

    var cloud = ObservationHistoryCloudClient.live

    func preview(observationID: String, analysisID: UUID, container: ModelContainer) async throws -> Preview {
        let baseline = try ConfirmedSpeciesReviewPersistence.transaction {
            try Baseline(ObservationHistorySyncService.enrolledScan(observationID, context: ModelContext(container)))
        }
        guard analysisID != UUID(uuidString: observationID) else { throw ObservationHistoryError.invalidPage }
        let lease = try cloud.begin(baseline.owner)
        defer { cloud.finish(lease) }
        guard lease.session.userID == baseline.owner, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let request = ObservationHistoryStateRequest(observation_id: observationID.lowercased(), analysis_id: analysisID.uuidString.lowercased())
        let bytes = try await cloud.fetchState(request)
        try Task.checkCancellation()
        guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let state = try ObservationHistoryState.decode(bytes, request: request, ownerID: baseline.owner)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
                let scan = try ObservationHistorySyncService.enrolledScan(observationID, context: context)
                let fresh = try Baseline(scan)
                guard fresh.owner == baseline.owner else { throw ObservationHistoryError.accountChanged }
                guard fresh == baseline else { throw AdmissionError.conflictingRevision }
                guard state.revision >= fresh.revision else { throw AdmissionError.staleRevision }
                // Preview cannot advance the observation's acknowledged revision:
                // that would hide a changed selection/authority from normal sync.
                guard state.revision == fresh.revision else { throw AdmissionError.refreshRequired }
                guard state.selectedAnalysisID == fresh.selected else { throw AdmissionError.conflictingRevision }
                _ = try ObservationHistorySyncService.insert([state.result], into: scan, ownerID: baseline.owner, context: context)
                let display = try ObservationHistoryStateCache.admit(state, scan: scan, context: context)
                try Task.checkCancellation()
                guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
                if context.hasChanges { try context.save() }
                return Preview(state: state, display: display)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private struct Baseline: Equatable {
        let owner: UUID
        let selected: UUID
        let revision: Int

        init(_ scan: LocalScanRecord) throws {
            guard let owner = scan.analysisOwnerAccountID.flatMap(UUID.init(uuidString:)),
                  let selected = scan.selectedAnalysisID.flatMap(UUID.init(uuidString:)),
                  let revision = scan.observationStateRevision else { throw ObservationHistoryError.unavailable }
            self.owner = owner
            self.selected = selected
            self.revision = revision
        }
    }
}
