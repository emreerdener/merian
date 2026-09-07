import Foundation

// MARK: - Background Inference Generation Lifecycle

extension OfflineQueueManager {
    func claimInferenceGeneration(
        scanId: String,
        proposedGeneration: UUID?
    ) -> UUID? {
        if let proposedGeneration,
           retiredInferenceGenerations.contains(proposedGeneration) {
            return nil
        }
        if let currentGeneration = activeInferenceGenerations[scanId] {
            guard currentGeneration == proposedGeneration else {
                MerianLog.data.debug(
                    "claimInferenceGeneration: ignored stale callback scanId=\(scanId, privacy: .public)"
                )
                return nil
            }
            return currentGeneration
        }

        let generation = proposedGeneration ?? UUID()
        activeInferenceGenerations[scanId] = generation
        SyncStateManager.shared.beginInferencing(generation: generation)
        return generation
    }

    func isInferenceGenerationCurrent(
        scanId: String,
        expectedGeneration: UUID?
    ) -> Bool {
        activeInferenceGenerations[scanId] == expectedGeneration
    }

    /// Closes process-local inference ownership after its durable owner has
    /// completed or been retired. Cross-file dispatch and background-transfer
    /// callers must establish durable retirement before invoking this method.
    func finishInferenceGeneration(
        scanId: String,
        generation: UUID
    ) {
        inferenceStatusProbeTasks.cancel(scanId, ifOwnedBy: generation)
        retiredInferenceGenerations.insert(generation)
        SyncStateManager.shared.completeSync(generation: generation)

        guard activeInferenceGenerations[scanId] == generation else { return }
        activeInferenceGenerations[scanId] = nil
        inferenceDispatchDates[scanId] = nil
    }
}
