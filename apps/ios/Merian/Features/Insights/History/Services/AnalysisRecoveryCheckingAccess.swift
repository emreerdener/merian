import Foundation
import SwiftData

@MainActor
extension AnalysisRecoveryCheckingModel.Access {
    /// Common account/container validity outlives the sheet. The exact media
    /// owner independently revalidates execution immediately before its I/O.
    static func prepared(identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                         isCurrent: @escaping @MainActor @Sendable () -> Bool,
                         validateOperation: @escaping () throws -> Void,
                         check: @escaping () async throws -> Bool) -> Self {
        typealias Store = ObservationReanalysisRecoveryPresentationStore
        return Self(isCurrent: isCurrent, reserve: {
            try validateOperation()
            let snapshot = try Store.read(identity, container: container, isCurrent: isCurrent)
            // Nil means a positively decoded spent budget, never a failed or
            // missing operation. Explicit exact checks can continue without a
            // renewed spinner; the existing owner still enforces single-flight.
            if snapshot.value.needsAttention { return nil }
            let interval = try Store.reserve(snapshot, container: container, isCurrent: isCurrent,
                validateOperation: validateOperation)
            return .init(allowance: interval.allowance, settle: { elapsed in
                _ = try Store.settle(interval, elapsed: elapsed, container: container, isCurrent: isCurrent)
            })
        }, check: check)
    }
}
