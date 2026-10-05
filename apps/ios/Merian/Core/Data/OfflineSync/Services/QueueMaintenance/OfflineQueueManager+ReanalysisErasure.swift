import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Only called with child IDs returned by a committed parent erasure.
    /// Refetch after suspension: a surviving row must never lose its transport.
    func finishReanalysisErasure(_ childIDs: [String], in container: ModelContainer) async {
        guard !childIDs.isEmpty, modelContext?.container === container else { return }
        let tasks = await backgroundSession.allTasks
        guard modelContext?.container === container else { return }
        for id in Set(childIDs) {
            let context = ModelContext(container)
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id })
            query.fetchLimit = 1
            do {
                guard try context.fetch(query).isEmpty else { continue }
            } catch {
                MerianLog.data.error("Reanalysis erasure: queue lookup failed; retaining runtime ownership.")
                continue
            }
            deferredLiveUploadScanIds.remove(id)
            userRequestedLargeUploadScanIds.remove(id)
            uploadPreparationGenerations[id] = nil
            latestUploadGenerations[id] = UUID()
            uploadCompletionStates[id] = nil
            inferencePreparationGenerations[id] = nil
            inferenceStatusProbeTasks.cancel(id)
            serverIngestionPollTasks.cancel(id)
            inferenceRetryTasks.cancel(id)
            foregroundInferenceRetirementTasks.cancel(id)
            foregroundInferenceGenerations[id] = nil
            startedForegroundInferenceGenerations[id] = nil
            scanIngestionJobStates[id] = nil
            if let generation = activeInferenceGenerations[id] {
                finishInferenceGeneration(scanId: id, generation: generation)
            }
            for task in tasks {
                guard let description = task.taskDescription else { continue }
                if MediaStagingContract.uploadTaskDescription(description, belongsTo: id)
                    || InferenceURLSessionTaskContract.parse(description)?.scanId == id {
                    task.cancel()
                }
            }
        }
        await drainPendingReanalysisErasures(in: container)
        updateUnsyncedItemCount()
    }

    func drainPendingReanalysisErasures(in container: ModelContainer) async {
        await reanalysisErasureOwner.drain(container: container, isCurrent: { [weak self] in
            self?.modelContext?.container === container
        })
    }

    func requestReanalysisErasureRecovery() {
        guard !TestExecutionCoordinator.isRunningTests, let container = modelContext?.container else { return }
        Task { await drainPendingReanalysisErasures(in: container) }
    }
}
