import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Explicitly deletes an offline queued scan immediately.
    /// Cancels any in-flight background uploads and purges the item from disk.
    @discardableResult
    func deleteQueuedScan(
        scanId: String,
        explicitlyAdoptedMediaPaths: [String] = [],
        preservePreferredGoalHint: Bool = false,
        inferenceExpectation: InferenceGenerationExpectation? = nil,
        foregroundInferenceExpectation: ForegroundInferenceGenerationExpectation? = nil,
        serverPollTokenToPreserve: UUID? = nil
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return false
        }
        let didDelete = await deleteQueuedScanAssumingPersistenceLock(
            scanId: scanId,
            explicitlyAdoptedMediaPaths: explicitlyAdoptedMediaPaths,
            preservePreferredGoalHint: preservePreferredGoalHint,
            inferenceExpectation: inferenceExpectation,
            foregroundInferenceExpectation: foregroundInferenceExpectation,
            serverPollTokenToPreserve: serverPollTokenToPreserve
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didDelete
    }

    private func deleteQueuedScanAssumingPersistenceLock(
        scanId: String,
        explicitlyAdoptedMediaPaths: [String],
        preservePreferredGoalHint: Bool,
        inferenceExpectation: InferenceGenerationExpectation?,
        foregroundInferenceExpectation: ForegroundInferenceGenerationExpectation?,
        serverPollTokenToPreserve: UUID?
    ) async -> Bool {
        let completedInference =
            inferenceExpectation != nil ||
            foregroundInferenceExpectation != nil
        if let foregroundInferenceExpectation {
            guard foregroundInferenceGenerations[scanId]
                    == foregroundInferenceExpectation.generation,
                  activeInferenceGenerations[scanId] == nil else {
                MerianLog.data.debug(
                    "deleteQueuedScan: ignored stale foreground inference owner scanId=\(scanId, privacy: .public)"
                )
                return false
            }
            guard let container = modelContext?.container else { return false }
            let validationActor = BackgroundDatabaseActor(
                modelContainer: container
            )
            guard await validationActor
                .liveInferenceGenerationIsCurrentAssumingPersistenceLock(
                    scanId: scanId,
                    expectedGeneration: foregroundInferenceExpectation.generation
                ) else {
                MerianLog.data.debug(
                    "deleteQueuedScan: durable foreground inference owner changed scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        } else if inferenceExpectation != nil {
            // A background result must never tear down a foreground owner. The
            // normal handoff prevents these states from overlapping; this guard
            // makes that invariant fail closed if a caller regresses.
            guard foregroundInferenceGenerations[scanId] == nil else {
                return false
            }
        }
        if let inferenceExpectation {
            guard activeInferenceGenerations[scanId]
                    == inferenceExpectation.generation else {
                MerianLog.data.debug(
                    "deleteQueuedScan: ignored stale inference owner scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }
        if let expectedGeneration = inferenceExpectation?.generation {
            guard let container = modelContext?.container else { return false }
            let validationActor = BackgroundDatabaseActor(
                modelContainer: container
            )
            guard await validationActor
                .inferenceGenerationIsCurrentAssumingPersistenceLock(
                    scanId: scanId,
                    expectedGeneration: expectedGeneration
                ) else {
                MerianLog.data.debug(
                    "deleteQueuedScan: durable inference owner changed scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }
        if let serverPollTokenToPreserve {
            guard serverIngestionPollTasks.isCurrent(
                scanId,
                token: serverPollTokenToPreserve
            ) else {
                MerianLog.data.debug(
                    "deleteQueuedScan: ignored stale server-poll owner scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }

        // 1. Cancel in-flight URLSession tasks (both upload chunks and inference download).
        let allTasks = await backgroundSession.allTasks
        if let foregroundInferenceExpectation {
            guard !Task.isCancelled,
                  foregroundInferenceGenerations[scanId]
                    == foregroundInferenceExpectation.generation,
                  activeInferenceGenerations[scanId] == nil else {
                MerianLog.data.debug(
                    "deleteQueuedScan: foreground owner changed while enumerating tasks scanId=\(scanId, privacy: .public)"
                )
                return false
            }
            guard let container = modelContext?.container else { return false }
            let validationActor = BackgroundDatabaseActor(
                modelContainer: container
            )
            guard await validationActor
                .liveInferenceGenerationIsCurrentAssumingPersistenceLock(
                    scanId: scanId,
                    expectedGeneration:
                        foregroundInferenceExpectation.generation
                ),
                foregroundInferenceGenerations[scanId]
                    == foregroundInferenceExpectation.generation,
                activeInferenceGenerations[scanId] == nil,
                !Task.isCancelled else {
                MerianLog.data.debug(
                    "deleteQueuedScan: durable foreground owner changed while enumerating tasks scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }
        if let inferenceExpectation {
            guard activeInferenceGenerations[scanId]
                    == inferenceExpectation.generation else {
                MerianLog.data.debug(
                    "deleteQueuedScan: owner changed while enumerating tasks scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }
        if let serverPollTokenToPreserve {
            guard !Task.isCancelled,
                  serverIngestionPollTasks.isCurrent(
                    scanId,
                    token: serverPollTokenToPreserve
                  ) else {
                MerianLog.data.debug(
                    "deleteQueuedScan: server-poll owner changed while enumerating tasks scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }

        // Clear in-process ownership only after the suspension point above has
        // revalidated the caller. A stale delete must not cancel replacement work.
        deferredLiveUploadScanIds.remove(scanId)
        if let foregroundInferenceExpectation {
            guard foregroundInferenceGenerations[scanId]
                    == foregroundInferenceExpectation.generation else {
                return false
            }
        }
        latestUploadGenerations[scanId] = nil
        uploadCompletionStates[scanId] = nil
        if inferenceExpectation == nil {
            inferenceStatusProbeTasks.cancel(scanId)
        }
        if serverPollTokenToPreserve == nil {
            serverIngestionPollTasks.cancel(scanId)
        }
        inferenceRetryTasks.cancel(scanId)
        scanIngestionJobStates[scanId] = nil
        for task in allTasks {
            if let desc = task.taskDescription,
               MediaStagingContract.uploadTaskDescription(desc, belongsTo: scanId)
                || InferenceURLSessionTaskContract.parse(desc)?.scanId == scanId {
                task.cancel()
            }
        }

        // 2. Delete from SwiftData and disk.
        guard let context = modelContext else { return false }
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let scan: OfflineQueuedScan?
        do {
            scan = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug("deleteQueuedScan: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            return false
        }
        guard let scan else {
            let job: OfflineJobRecord?
            do {
                job = try context.fetchOfflineJob(
                    id: Self.scanIngestionJobId(scanId: scanId)
                )
            } catch {
                MerianLog.data.error(
                    "deleteQueuedScan: job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
                )
                return false
            }
            if completedInference, let job, job.status != .complete {
                job.status = .complete
                job.updatedAt = Date()
                job.nextRunAt = nil
                job.lastErrorCode = nil
                job.lastErrorMessage = nil
                job.lastHTTPStatus = nil
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    scanId: scanId,
                    kind: .completed,
                    message: "Queued scan inference completed."
                ))
                do {
                    try context.save()
                    OfflineJobScheduler.shared.scheduleNextPersistedWake(
                        using: self
                    )
                } catch {
                    context.rollback()
                    return false
                }
            }
            if preservePreferredGoalHint {
                clearForegroundInferenceOwnershipAfterDeletion(
                    scanId: scanId,
                    inferenceExpectation: inferenceExpectation,
                    foregroundInferenceExpectation:
                        foregroundInferenceExpectation
                )
                return true
            }
            context.deletePreferredGoalHint(scanId: scanId)
            do {
                try context.save()
                clearForegroundInferenceOwnershipAfterDeletion(
                    scanId: scanId,
                    inferenceExpectation: inferenceExpectation,
                    foregroundInferenceExpectation:
                        foregroundInferenceExpectation
                )
                return true
            } catch {
                context.rollback()
                return false
            }
        }

        func pathVariants(_ path: String) -> [String] {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }

            var variants = Set([trimmed])
            if trimmed.starts(with: "file://"), let url = URL(string: trimmed), url.isFileURL {
                variants.insert(url.path)
                variants.insert(url.lastPathComponent)
            } else if trimmed.hasPrefix("/") {
                let url = URL(fileURLWithPath: trimmed)
                variants.insert(url.path)
                variants.insert(url.lastPathComponent)
            } else {
                variants.insert(URL.documentsDirectory.appendingPathComponent(trimmed).path)
                variants.insert(URL(fileURLWithPath: trimmed).lastPathComponent)
            }
            return Array(variants)
        }

        let adoptedMediaPaths = Set(explicitlyAdoptedMediaPaths.flatMap(pathVariants))
        var pathsToDelete: [String] = []

        func appendDeletionCandidate(_ reference: StoredMediaReference) {
            guard !reference.isRemote else { return }
            var referenceVariants = pathVariants(reference.serializedPath)
            if let resolvedURL = reference.resolvedURL {
                referenceVariants.append(contentsOf: pathVariants(resolvedURL.path))
            }
            let variants = Set(referenceVariants)
            guard variants.isDisjoint(with: adoptedMediaPaths) else { return }

            if let targetURL = reference.resolvedURL {
                pathsToDelete.append(targetURL.path)
            } else {
                pathsToDelete.append(reference.serializedPath)
            }
        }

        for item in scan.capturedMediaSnapshot.items {
            switch item {
            case .image(let reference):
                appendDeletionCandidate(reference)
            case .audio(let reference):
                appendDeletionCandidate(reference)
            case .video(let reference):
                appendDeletionCandidate(reference.video)
                if let thumbnail = reference.thumbnail {
                    appendDeletionCandidate(thumbnail)
                }
                if let audio = reference.audio {
                    appendDeletionCandidate(audio)
                }
            case .description:
                break
            }
        }

        for inferenceImagePath in scan.inferenceImagePaths ?? [] {
            appendDeletionCandidate(.documents(inferenceImagePath))
        }

        let job: OfflineJobRecord?
        do {
            job = try context.fetchOfflineJob(
                id: Self.scanIngestionJobId(scanId: scanId)
            )
        } catch {
            MerianLog.data.error(
                "deleteQueuedScan: job fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        if let job {
            job.status = completedInference ? .complete : .cancelled
            job.updatedAt = Date()
            job.nextRunAt = nil
            if completedInference {
                job.lastErrorCode = nil
                job.lastErrorMessage = nil
                job.lastHTTPStatus = nil
            }
        }
        context.insert(OfflineQueueEvent(
            jobId: Self.scanIngestionJobId(scanId: scanId),
            scanId: scanId,
            kind: completedInference ? .completed : .cancelled,
            message: completedInference
                ? "Queued scan inference completed."
                : "Queued scan was removed locally."
        ))
        if !preservePreferredGoalHint {
            context.deletePreferredGoalHint(scanId: scanId)
        }
        context.delete(scan)
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            clearForegroundInferenceOwnershipAfterDeletion(
                scanId: scanId,
                inferenceExpectation: inferenceExpectation,
                foregroundInferenceExpectation:
                    foregroundInferenceExpectation
            )
            await FileIOActor.shared.deleteFiles(at: Array(Set(pathsToDelete)))
            updateUnsyncedItemCount()
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            return true
        } catch {
            context.rollback()
            MerianLog.data.error("deleteQueuedScan: save failed for \(scanId, privacy: .private): \(error, privacy: .private)")
            updateUnsyncedItemCount()
            return false
        }
    }

    private func clearForegroundInferenceOwnershipAfterDeletion(
        scanId: String,
        inferenceExpectation: InferenceGenerationExpectation?,
        foregroundInferenceExpectation:
            ForegroundInferenceGenerationExpectation?
    ) {
        if let foregroundInferenceExpectation {
            if foregroundInferenceGenerations[scanId]
                == foregroundInferenceExpectation.generation {
                foregroundInferenceGenerations[scanId] = nil
                if startedForegroundInferenceGenerations[scanId]
                    == foregroundInferenceExpectation.generation {
                    startedForegroundInferenceGenerations[scanId] = nil
                }
                foregroundInferenceRetirementTasks.cancel(
                    scanId,
                    ifOwnedBy: foregroundInferenceExpectation.generation
                )
            }
        } else if inferenceExpectation == nil {
            // No expectation denotes an explicit user/system deletion.
            foregroundInferenceGenerations[scanId] = nil
            startedForegroundInferenceGenerations[scanId] = nil
            foregroundInferenceRetirementTasks.cancel(scanId)
        }
    }

    /// Permanently removes all `.failed` `OfflineQueuedScan` records and their image files from disk.
    /// Called at cleanup points (e.g., after a successful sync cycle or on app foreground).
    func purgeSoftDeletedRecords() {
        guard let context = modelContext else { return }
        let failedRaw = ScanQueueState.failed.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == failedRaw && !$0.queueNeedsAttention }
        )
        descriptor.fetchLimit = 500

        do {
            let failedScans = try context.fetch(descriptor)
            guard !failedScans.isEmpty else { return }
            var pathsToDelete: [String] = []
            for scan in failedScans {
                let scanId = scan.id
                for item in scan.capturedMediaSnapshot.items {
                    switch item {
                    case .image(let reference), .audio(let reference):
                        if let targetURL = reference.resolvedURL, !reference.isRemote {
                            pathsToDelete.append(targetURL.path)
                        } else {
                            pathsToDelete.append(reference.serializedPath)
                        }
                    case .video(let reference):
                        for mediaReference in [reference.video, reference.thumbnail, reference.audio].compactMap({ $0 }) {
                            if let targetURL = mediaReference.resolvedURL, !mediaReference.isRemote {
                                pathsToDelete.append(targetURL.path)
                            } else {
                                pathsToDelete.append(mediaReference.serializedPath)
                            }
                        }
                    case .description:
                        break
                    }
                }
                context.deletePreferredGoalHint(scanId: scanId)
                context.delete(scan)
                if let job = try? context.fetchOfflineJob(
                    id: Self.scanIngestionJobId(scanId: scanId)
                ) {
                    job.status = .cancelled
                    job.updatedAt = Date()
                }
            }
            try context.save()
            Task {
                await FileIOActor.shared.deleteFiles(at: pathsToDelete)
            }
            updateUnsyncedItemCount()
        } catch {
            context.rollback()
            MerianLog.data.debug("purgeSoftDeletedRecords: operation failed: \(error, privacy: .private)")
            updateUnsyncedItemCount()
        }
    }
}
