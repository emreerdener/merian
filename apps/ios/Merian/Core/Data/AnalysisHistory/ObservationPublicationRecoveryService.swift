import Foundation
import SwiftData

/// Two independent historical facts, never permission to replace a saved operation.
struct ObservationPublicationTargetRecovery: Equatable {
    enum Remote: Equatable { case absent, found(ObservationPublicationReceipt) }
    let local: ObservationPublicationOperationStatus?
    let remote: Remote
}

/// Read-only recovery deliberately has no request, save, acknowledgement or wake capability.
@MainActor
struct ObservationPublicationRecoveryService {
    var cloud: ObservationHistoryCloudClient
    let fetch: (ObservationPublicationTargetRequest, UUID) async throws -> ObservationPublicationReceipt?

    func read(ownerID: UUID, observationID: UUID, container: ModelContainer,
              isCurrent: () -> Bool) async throws -> ObservationPublicationReceipt? {
        func current() -> Bool { !Task.isCancelled && isCurrent() }
        _ = try ObservationPublicationOperationStatus.readTarget(ownerID: ownerID, observationID: observationID,
            container: container, isCurrent: current)
        let lease = try cloud.begin(ownerID)
        defer { cloud.finish(lease) }
        guard current(), lease.session.userID == ownerID, cloud.isCurrent(lease) else {
            throw ObservationHistoryError.accountChanged
        }
        let receipt = try await fetch(.init(observationID: observationID), ownerID)
        guard current(), cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        guard receipt == nil || receipt?.observationID == observationID else { throw MerianError.invalidResponse }
        _ = try ObservationPublicationOperationStatus.readTarget(ownerID: ownerID, observationID: observationID,
            container: container, isCurrent: current)
        return receipt
    }
}
