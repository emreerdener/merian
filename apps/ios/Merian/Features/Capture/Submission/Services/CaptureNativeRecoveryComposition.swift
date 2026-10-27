import Foundation

extension CaptureNativeRecoveryModel {
    /// Construction is presentation-only. The existing AppDI lifetime owns
    /// admission and shutdown; each explicit read uses its retained owner.
    static func app(ownerID: UUID, diContainer: AppDIContainer) -> CaptureNativeRecoveryModel? {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              diContainer.supabaseManager.currentUser?.id == ownerID,
              let container = diContainer.offlineQueueManager.modelContext?.container else { return nil }
        let manager = diContainer.supabaseManager
        let generation = manager.authSessionGeneration
        let current = {
            manager.currentUser?.id == ownerID && manager.authSessionGeneration == generation
                && diContainer.offlineQueueManager.modelContext?.container === container
                && !manager.libraryAccountRecoveryRequired && !manager.librarySignOutRecoveryPending
                && (manager.libraryTransferResult == .completed || manager.isGuestUser)
        }
        return .init(ownerID: ownerID, isCurrent: current, discover: {
            guard current() else { throw SharedMediaStorageFailure.stale }
            let owner = try await diContainer.nativeMediaOwnerForFeature()
            guard current() else { throw SharedMediaStorageFailure.stale }
            return try await owner.discoverAppReceivedCandidates()
        })
    }
}
