import Foundation
import SwiftData

/// Explicit tap only; opening History/status never calls this capability.
@MainActor
struct SavedIdentificationReanalysisAccess {
    struct Request {
        let resolve: () async throws -> IdentificationHistoryReanalysisAction
    }
    let prepare: (String, ObservationHistoryStateSyncService.ReviewBaseline, ModelContainer) throws -> Request
    let dispatch: (HistoricalReanalysisTarget) -> Void

    static func prepared(cloud: ObservationHistoryCloudClient, enrollment: ObservationHistoryEnrollmentOwner,
                         currentOwner: @escaping () -> UUID?, generation: @escaping () -> UInt64,
                         sessionIsCurrent: @escaping (AuthTransitionSession) -> Bool,
                         containerIsCurrent: @escaping (ModelContainer) -> Bool,
                         dispatch: @escaping (HistoricalReanalysisTarget) -> Void) -> Self {
        Self(prepare: { id, displayed, container in
            try Task.checkCancellation()
            let observation = try ObservationHistoryPage.uuid(id)
            guard let owner = currentOwner(), containerIsCurrent(container) else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation(), lease = try cloud.begin(owner)
            defer { cloud.finish(lease) }
            let session = lease.session
            let current = {
                currentOwner() == owner && generation() == expectedGeneration
                    && sessionIsCurrent(session) && containerIsCurrent(container)
            }
            guard session.userID == owner, cloud.isCurrent(lease), current() else { throw ObservationHistoryError.accountChanged }
            if displayed.owner.isEmpty && displayed.selected == nil {
                guard try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container) == displayed else {
                    throw ObservationHistoryEnrollmentService.AdmissionError.localStateChanged
                }
                return Request(resolve: {
                    try Task.checkCancellation()
                    guard current() else { throw ObservationHistoryError.accountChanged }
                    let analysis = try await enrollment.enroll(observation: observation, owner: owner, generation: expectedGeneration,
                        container: container, cloud: cloud, expectedBaseline: displayed, isCurrent: current)
                    try Task.checkCancellation()
                    guard current() else { throw ObservationHistoryError.accountChanged }
                    let baseline = try ObservationHistoryStateSyncService.displayBaseline(observation: observation, container: container)
                    guard baseline.retainsIdentification(of: displayed) else { throw ObservationHistoryError.resultConflict }
                    return try action(observation: observation, analysis: analysis, owner: owner, container: container,
                        cloud: cloud, current: current)
                })
            }
            guard try ObservationHistoryStateSyncService.displayBaseline(observation: observation, container: container) == displayed else {
                throw ObservationHistoryError.resultConflict
            }
            let analysis = try ObservationHistoryPage.uuid(displayed.selected)
            let frozen = try action(observation: observation, analysis: analysis, owner: owner, container: container, cloud: cloud, current: current)
            return Request(resolve: {
                try Task.checkCancellation()
                _ = try frozen.resolve()
                return frozen
            })
        }, dispatch: dispatch)
    }

    private static func action(observation: UUID, analysis: UUID, owner: UUID, container: ModelContainer,
                               cloud: ObservationHistoryCloudClient, current: @escaping () -> Bool) throws -> IdentificationHistoryReanalysisAction {
        let listing = ObservationHistoryListingService(cloud: cloud)
        let baseline = try listing.context(observationID: observation.uuidString, container: container)
        guard baseline.owner == owner, baseline.selected == analysis, baseline.pendingOperation == nil else {
            throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
        }
        let source = try ObservationReanalysisSource.capture(observationID: observation, analysisID: analysis, ownerID: owner, container: container)
        let display = try ObservationHistoryStateSyncService.displayBaseline(observation: observation, container: container)
        let action = IdentificationHistoryReanalysisAction {
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            guard try listing.context(observationID: observation.uuidString, container: container) == baseline,
                  try ObservationHistoryStateSyncService.displayBaseline(observation: observation, container: container) == display else {
                throw ObservationHistoryPreviewService.AdmissionError.refreshRequired
            }
            try source.validate(container: container)
            return .init(observationID: observation, analysisID: analysis, ownerID: owner)
        }
        _ = try action.resolve()
        return action
    }
}
