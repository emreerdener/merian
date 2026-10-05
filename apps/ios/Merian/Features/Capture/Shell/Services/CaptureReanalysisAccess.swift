import Foundation
import SwiftData

/// Explicit opt-in boundary. Live Capture dependencies remain nil until activation is qualified.
@MainActor
struct CaptureReanalysisAccess {
    let open: (HistoricalReanalysisTarget, ModelContainer) throws -> CaptureReanalysisEditor

    static func prepared(ownership: ObservationReanalysisPreparationOwner, account: ObservationHistoryCloudClient? = nil,
                         isCurrentOwner: @escaping @MainActor () -> UUID?,
                         generation: @escaping @MainActor () -> UInt64,
                         requestCleanup: @escaping @MainActor () -> Void) -> Self {
        let account = account ?? .live
        return Self(open: { target, container in
            guard isCurrentOwner() == target.ownerID else { throw ObservationHistoryError.accountChanged }
            let expectedGeneration = generation()
            let lease = try account.begin(target.ownerID)
            defer { account.finish(lease) }
            guard lease.session.userID == target.ownerID, account.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            let source = try ObservationReanalysisSource.capture(observationID: target.observationID,
                analysisID: target.analysisID, ownerID: target.ownerID, container: container)
            let current = { isCurrentOwner() == target.ownerID && generation() == expectedGeneration }
            guard current() else { throw ObservationHistoryError.accountChanged }
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            return CaptureReanalysisEditor(source: source, container: container, account: account,
                loader: CaptureReanalysisEvidenceLoader(account: account),
                producer: ObservationReanalysisProducer(files: ObservationReanalysisFileStore(documents: documents), ownership: ownership, account: account),
                isCurrent: current, requestCleanup: requestCleanup)
        })
    }
}
