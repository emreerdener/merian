import Foundation

extension OfflineQueueManager {
    func isUploadGenerationCurrent(
        scanId: String,
        generation: UUID?
    ) -> Bool {
        if let preparationGeneration = uploadPreparationGenerations[scanId] {
            return generation == preparationGeneration
        }
        if let latestGeneration = latestUploadGenerations[scanId] {
            return generation == latestGeneration
        }
        // After process launch there may be a legacy or generation-tagged
        // URLSession task but no in-memory ownership yet. It remains eligible
        // until a new preparation claims this scan.
        return true
    }

    func invalidateUploadGeneration(
        scanId: String,
        generation: UUID?
    ) {
        guard isUploadGenerationCurrent(
            scanId: scanId,
            generation: generation
        ) else {
            return
        }
        // A distinct fence remains until the next uploader claims this scan.
        // It also fences legacy generation-less sibling callbacks after launch.
        clearUploadCompletionState(
            scanId: scanId,
            generation: generation
        )
        latestUploadGenerations[scanId] = UUID()
    }

    func isCurrentUploadSync(_ generation: UUID) -> Bool {
        syncGeneration == generation
    }

    @discardableResult
    func finishUploadSync(generation: UUID?) -> Bool {
        if let generation {
            guard syncGeneration == generation else {
                MerianLog.data.debug(
                    "finishUploadSync: ignored stale generation=\(generation.uuidString, privacy: .private)"
                )
                return false
            }
            SyncStateManager.shared.completeUploadPhase(generation: generation)
        } else {
            // Compatibility for upload tasks attached by an older app build.
            guard syncGeneration == nil else { return false }
        }

        syncGeneration = nil
        syncTask = nil
        isSyncing = false
        return true
    }

    func expireUploadSync(generation: UUID) {
        guard isCurrentUploadSync(generation) else {
            MerianLog.data.debug(
                "expireUploadSync: ignored stale generation=\(generation.uuidString, privacy: .private)"
            )
            return
        }
        syncTask?.cancel()
        uploadPreparationGenerations = uploadPreparationGenerations.filter {
            $0.value != generation
        }
        _ = finishUploadSync(generation: generation)
    }
}
