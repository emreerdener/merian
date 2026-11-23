import Foundation

/// Explicit continuation of a completed observation. Result success is already
/// durable; an error here means History or local cleanup remains pending. This
/// adapter has no upload, inference, funding-admission or baseline-selection API.
@MainActor
struct CaptureCompletedHistoryContinuation {
    typealias Candidate = SharedMediaCaptureCompletedRecovery.Candidate
    let requireCurrent: () throws -> Void
    let inspect: (Candidate) async throws -> Candidate
    let enroll: (UUID) async throws -> Void
    let release: (Candidate) async throws -> Void

    func finish(_ candidate: Candidate) async throws {
        try requireCurrent(); try Task.checkCancellation()
        var current = try await inspect(candidate)
        try requireSameObservation(current, expected: candidate)
        try requireCurrent(); try Task.checkCancellation()
        if !current.releaseStarted {
            // The existing enrollment owner reuses its saved intent and checks
            // the original baseline independently of any later selected child.
            try await enroll(current.scanID)
            try requireCurrent(); try Task.checkCancellation()
            current = try await inspect(current)
            try requireSameObservation(current, expected: candidate)
            try requireCurrent(); try Task.checkCancellation()
        }
        // A partial cleanup already has a durable History proof. Resume that
        // exact intent locally; do not recreate or reenroll a historical result.
        try await release(current)
        try requireCurrent(); try Task.checkCancellation()
    }

    private func requireSameObservation(_ current: Candidate, expected: Candidate) throws {
        guard current.scanID == expected.scanID, current.generation == expected.generation,
              !expected.releaseStarted || current.releaseStarted else { throw SharedMediaStorageFailure.stale }
    }

    static func app(ownerID: UUID, diContainer: AppDIContainer) async throws -> Self {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let container = diContainer.offlineQueueManager.modelContext?.container else {
            throw SharedMediaStorageFailure.closed
        }
        let manager = diContainer.supabaseManager, generation = manager.authSessionGeneration
        let current = {
            manager.currentUser?.id == ownerID && manager.authSessionGeneration == generation
                && diContainer.offlineQueueManager.modelContext?.container === container
                && !manager.isAuthTransitionInProgress && !manager.libraryAccountRecoveryRequired
                && !manager.librarySignOutRecoveryPending
                && (manager.libraryTransferResult == .completed || manager.isGuestUser)
        }
        let requireCurrent = { guard current() else { throw SharedMediaStorageFailure.closed } }
        try requireCurrent(); try Task.checkCancellation()
        let owner = try await diContainer.nativeMediaLifecycle.nativeMediaOwnerForCaptureDraft()
        try requireCurrent(); try Task.checkCancellation()
        return .init(requireCurrent: requireCurrent, inspect: { candidate in
            try requireCurrent()
            let current = try await owner.inspectCompletedAppCapture(candidate)
            try requireCurrent()
            return current
        }, enroll: { observation in
            try requireCurrent()
            _ = try await diContainer.offlineQueueManager.historyEnrollmentOwner.continueInitialHistory(
                observation: observation, owner: ownerID, generation: generation, container: container,
                cloud: .live(manager: manager), isCurrent: current)
            try requireCurrent()
        }, release: { candidate in
            try requireCurrent()
            // Release independently joins current completion, funding and the
            // exact acknowledged baseline; enrollment's UUID is not authority.
            _ = try await owner.releaseAppCaptureSubmission(scanID: candidate.scanID, generation: candidate.generation)
            try requireCurrent()
        })
    }
}
