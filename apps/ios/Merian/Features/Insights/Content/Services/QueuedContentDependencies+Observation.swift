import Foundation
import SwiftData

extension QueuedContentDependencies {
    static func qualifiedObservation(_ di: AppDIContainer) -> ObservationRead? {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified else { return nil }
        return { queue, scanID, isPresented in
            let manager = di.supabaseManager
            guard queue === di.offlineQueueManager,
                  let owner = manager.currentUser?.id, let container = queue.modelContext?.container else {
                throw MerianError.invalidResponse
            }
            let generation = manager.authSessionGeneration
            let lease = try manager.beginUnownedAccountBoundWork(expectedUserID: owner)
            defer { manager.finishAccountBoundWork(lease) }
            let current = {
                isPresented() && manager.currentUser?.id == owner && manager.authSessionGeneration == generation
                    && manager.allowsUnownedAccountBoundWork && queue.modelContext?.container === container
                    && !manager.libraryAccountRecoveryRequired && !manager.librarySignOutRecoveryPending
                    && (manager.libraryTransferResult == .completed || manager.isGuestUser)
            }
            let transport = MerianNetworkClient.shared.nativeReceivedStatusTransport()
            return try await readObservation(scanID: scanID, ownerID: owner, container: container,
                isCurrent: current, validateLease: {
                    guard manager.isAccountBoundWorkLeaseCurrent(lease) else { throw MerianError.invalidResponse }
                }, send: { scan, account, validate in
                    try await transport.perform(scanID: scan, ownerID: account, validate: validate)
                })
        }
    }

    /// Fresh account/queue/job evidence around the only network read. No writer,
    /// funding action, scheduler or result import belongs to this operation.
    static func readObservation(scanID: String, ownerID: UUID, container: ModelContainer,
                                isCurrent: @escaping @MainActor () -> Bool,
                                validateLease: @escaping NativeReceivedStatusTransport.Validator = {},
                                send: @escaping NativeReceivedStatusTransport.Send) async throws -> Observation {
        try Task.checkCancellation()
        guard isCurrent() else { throw MerianError.invalidResponse }
        let snapshot = try OfflineQueueDurableAuthorityReader.observation(scanId: scanID, ownerID: ownerID, from: container)
        let validate: NativeReceivedStatusTransport.Validator = {
            try Task.checkCancellation()
            guard isCurrent(),
                  try OfflineQueueDurableAuthorityReader.observation(scanId: scanID, ownerID: ownerID, from: container) == snapshot else {
                throw MerianError.invalidResponse
            }
        }
        let active: NativeReceivedStatusTransport.Validator = { try validateLease(); try validate() }
        try active()
        let bytes = try await send(snapshot.scanID, ownerID, active)
        try active()
        let value = try ScanObservationResponse.decode(bytes, ownerID: ownerID, scanID: snapshot.scanID)
        return Observation(value: value, validate: validate)
    }
}
