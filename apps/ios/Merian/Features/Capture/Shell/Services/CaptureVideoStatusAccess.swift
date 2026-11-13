import Foundation
import SwiftData

/// Inert local discovery. A page is never permission to create, retry or dispatch an operation.
@MainActor
struct CaptureVideoStatusAccess {
    struct Opened {
        let isCurrent: @MainActor () -> Bool
        let page: (ObservationVideoSavedStatus.Cursor?, Int, @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationVideoSavedStatus.Page
        var validate: @MainActor () throws -> Void = {}
    }
    let open: (UUID, UUID, ModelContainer) throws -> Opened

    static func prepared(account: ObservationHistoryCloudClient, owner: ObservationAudioStatusOwner,
                         reader: ObservationVideoSavedStatus,
                         currentOwner: @escaping @MainActor @Sendable () -> UUID?,
                         generation: @escaping @MainActor @Sendable () -> UInt64,
                         sessionIsCurrent: @escaping @MainActor @Sendable (AuthTransitionSession) -> Bool,
                         containerIsCurrent: @escaping @MainActor @Sendable (ModelContainer) -> Bool) -> Self {
        Self(open: { ownerID, observationID, container in
            guard currentOwner() == ownerID, containerIsCurrent(container) else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation(), lease = try account.begin(ownerID)
            defer { account.finish(lease) }
            let session = lease.session
            let current: @MainActor @Sendable () -> Bool = {
                currentOwner() == ownerID && generation() == expectedGeneration &&
                    sessionIsCurrent(session) && containerIsCurrent(container)
            }
            guard session.userID == ownerID, current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            try reader.validateParentScope(ownerID: ownerID, observationID: observationID, container: container, isCurrent: current)
            guard current(), account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            return Opened(isCurrent: current, page: { cursor, limit, presentationIsCurrent in
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                let page = try await owner.videoPage(ownerID: ownerID, observationID: observationID, session: session,
                    generation: expectedGeneration, after: cursor, limit: limit, container: container, reader: reader,
                    account: account, isCurrent: current)
                try Task.checkCancellation()
                guard current(), presentationIsCurrent() else { throw ObservationHistoryError.accountChanged }
                return page
            }, validate: {
                try reader.validateParentScope(ownerID: ownerID, observationID: observationID,
                    container: container, isCurrent: current)
            })
        })
    }
}
