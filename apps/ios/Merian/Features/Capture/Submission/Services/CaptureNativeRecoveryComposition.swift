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
        return .init(ownerID: ownerID, isCurrent: current,
            lifetime: { diContainer.nativeMediaLifetime }, discover: {
            guard current() else { throw SharedMediaStorageFailure.stale }
            let owner = try await diContainer.nativeMediaOwnerForFeature()
            guard current() else { throw SharedMediaStorageFailure.stale }
            return try await owner.discoverAppReceivedCandidates()
        })
    }
}

/// The model owns visibility; this access retains the original native save
/// attempts. Ordinary app composition cannot construct a persistence capability.
@MainActor
final class CaptureNativeRecoveryStatusAccess {
    struct Interval {
        let allowance: Duration
        let settle: (Duration) async throws -> Bool
    }
    let reserve: (SharedMediaNativeReceivedCandidate) async throws -> Interval?
    let check: (SharedMediaNativeReceivedCandidate) async throws -> Bool
    private init(reserve: @escaping (SharedMediaNativeReceivedCandidate) async throws -> Interval?,
                 check: @escaping (SharedMediaNativeReceivedCandidate) async throws -> Bool) {
        self.reserve = reserve; self.check = check
    }

    #if DEBUG
    /// Actual native transactions still require a disposable XCTest store.
    /// Failed/uncertain attempts remain retained; reconciliation never upgrades
    /// their original acknowledgement or creates another continuation.
    static func fixture(owner: SharedMediaNativeOriginalOwner,
                        send: @escaping NativeReceivedStatusTransport.Send) -> CaptureNativeRecoveryStatusAccess {
        var candidate: SharedMediaNativeReceivedCandidate?
        var attempt: SharedMediaNativeRecoveryPresentationAttempt?
        var blocked = false
        return .init(reserve: { selected in
            guard candidate == nil || candidate == selected else { throw SharedMediaStorageFailure.stale }
            candidate = selected
            guard !blocked else { return nil }
            blocked = true
            let reserved: SharedMediaNativeRecoveryPresentationAttempt
            if let previous = attempt {
                reserved = try await owner.reserveAgainAppRecoveryPresentationForTesting(previous)
            } else {
                reserved = try await owner.reserveAppRecoveryPresentationForTesting(selected)
            }
            attempt = reserved
            guard let allowance = reserved.visibleAllowance else { return nil }
            return Interval(allowance: allowance, settle: { elapsed in
                let settled = try await owner.settleAppRecoveryPresentationForTesting(reserved, elapsed: elapsed)
                attempt = settled
                blocked = !settled.acknowledged || settled.presentation.needsAttention
                return settled.acknowledged
            })
        }, check: { try await owner.checkAppReceivedStatus($0, send: send) })
    }
    #endif
}
