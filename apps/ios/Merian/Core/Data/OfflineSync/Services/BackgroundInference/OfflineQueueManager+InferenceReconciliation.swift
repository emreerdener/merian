import Foundation

extension OfflineQueueManager {
    /// Reconciles durable server-owned inference work that has no local task.
    ///
    /// This sweep deliberately delegates each candidate to the same recovery
    /// path used by status probes so server-complete and retryable outcomes
    /// retain one policy owner.
    func serverOwnedInferencingScanIds(
        excluding locallyActiveScanIds: Set<String>,
        reason: String,
        observedThrough: Date
    ) async -> Set<String> {
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              let context = modelContext else {
            return []
        }
        let dbActor = resolvedQueueDbActor(container: context.container)
        let candidateIds = await dbActor.fetchServerOwnedInferencingScanIds(
            excludingScanIds: locallyActiveScanIds,
            observedThrough: observedThrough
        )

        var retained = Set<String>()
        for scanId in candidateIds {
            let action = await recoverCompletedInferenceFromServer(
                scanId: scanId,
                reason: reason,
                expectedGeneration: nil
            )
            switch action {
            case .waitForServer, .retryAfter:
                retained.insert(scanId)
            case .recovered, .terminalFailure, .unresolved:
                break
            }
        }
        return retained
    }
}
