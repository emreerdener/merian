import Foundation

extension OfflineQueueManager {
    // MARK: - Upload Helpers

    /// Upgrades pre-WAV queue rows while holding the same per-scan lock used by
    /// inference claims. The database claim clears stale staged keys first;
    /// generated WAVs are adopted only by an exact durable commit.
    nonisolated func repairLegacyQueuedAudio(
        scanIds: [String],
        dbActor: BackgroundDatabaseActor,
        audioPreparer: @escaping LegacyQueuedAudioFilePreparer = {
            try await InferenceAudioPreparer.prepareLegacyQueuedFile(
                at: $0,
                scanId: $1
            )
        }
    ) async -> LegacyQueuedAudioRepairResult {
        var result = LegacyQueuedAudioRepairResult()

        for scanId in scanIds {
            if Task.isCancelled { break }
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: scanId
            )

            guard let candidate = await dbActor.claimLegacyQueuedAudioRepair(
                scanId: scanId
            ) else {
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: scanId
                )
                continue
            }
            result.claimedScanIds.insert(scanId)
            removeInterruptedLegacyQueuedAudioOutputs(
                scanId: scanId,
                retaining: candidate.retainedAudioFileNames
            )

            var preparedURLs: [URL] = []
            do {
                var replacements: [LegacyQueuedAudioRepairReplacement] = []
                for reference in candidate.references {
                    try Task.checkCancellation()
                    guard let localPath = reference.resolvedLocalPath else {
                        throw InferenceAudioPreparationError.sourceUnavailable
                    }
                    let preparedURL = try await audioPreparer(
                        URL(fileURLWithPath: localPath),
                        scanId
                    )
                    preparedURLs.append(preparedURL)
                    replacements.append(LegacyQueuedAudioRepairReplacement(
                        sourceStorage: reference.storage,
                        sourcePath: reference.path,
                        replacementFileName: preparedURL.lastPathComponent
                    ))
                }

                try Task.checkCancellation()
                let committed = await dbActor.commitLegacyQueuedAudioRepair(
                    scanId: scanId,
                    replacements: replacements
                )
                if committed {
                    result.repairedScanIds.insert(scanId)
                } else {
                    for preparedURL in preparedURLs {
                        try? FileManager.default.removeItem(at: preparedURL)
                    }
                }
            } catch is CancellationError {
                for preparedURL in preparedURLs {
                    try? FileManager.default.removeItem(at: preparedURL)
                }
                _ = await dbActor.finishLegacyQueuedAudioRepairFailure(
                    scanId: scanId,
                    cancelled: true
                )
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: scanId
                )
                break
            } catch {
                for preparedURL in preparedURLs {
                    try? FileManager.default.removeItem(at: preparedURL)
                }
                let didPersistFailure = await dbActor
                    .finishLegacyQueuedAudioRepairFailure(
                        scanId: scanId,
                        cancelled: false
                    )
                if didPersistFailure {
                    result.failedScanIds.insert(scanId)
                }
            }

            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
        }

        let completedResult = result
        await MainActor.run {
            for scanId in completedResult.claimedScanIds {
                self.uploadCompletionStates[scanId] = nil
                self.latestUploadGenerations[scanId] = nil
            }
            for scanId in completedResult.failedScanIds {
                self.releaseFundingForProvenPredispatchFailure(scanId: scanId)
            }
            if completedResult.didMutate {
                self.updateUnsyncedItemCount()
                AppDIContainer.shared.appEventPublisher.send(
                    .scanLibraryChanged
                )
            }
        }
        return completedResult
    }

    nonisolated private func removeInterruptedLegacyQueuedAudioOutputs(
        scanId: String,
        retaining retainedFileNames: Set<String>
    ) {
        let prefix = InferenceAudioPreparer.legacyQueueOutputPrefix(
            scanId: scanId
        )
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: .documentsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for candidate in candidates
        where candidate.lastPathComponent.hasPrefix(prefix)
            && candidate.pathExtension.lowercased() == "wav"
            && !retainedFileNames.contains(candidate.lastPathComponent) {
            try? FileManager.default.removeItem(at: candidate)
        }
    }

    nonisolated func currentMediaStagingUserId() async -> String? {
        await MainActor.run {
            let manager = SupabaseManager.shared
            guard let lease = try? manager.beginUnownedAccountBoundWork()
            else { return nil }
            defer { manager.finishAccountBoundWork(lease) }
            return lease.session.userID.uuidString
        }
    }

    nonisolated func prepareUploadItems(
        from scans: [PendingScanPayload],
        userId: String
    ) -> MediaStagingPreparation {
        var uploadItems: [ScanUploadItem] = []
        var uploadFiles: [StagingUploadFile] = []
        var rejectedScanIds: [String] = []

        for scan in scans {
            let scanItems = MediaStagingContract.uploadItems(for: scan, userId: userId)
            do {
                try MediaStagingContract.validateUploadBudget(scanItems)
                let scanUploadFiles = try MediaStagingContract.uploadFiles(for: scanItems)
                uploadItems.append(contentsOf: scanItems)
                uploadFiles.append(contentsOf: scanUploadFiles)
            } catch {
                MerianLog.data.error("prepareUploadItems: rejecting staged media for \(scan.id, privacy: .private): \(error, privacy: .private)")
                rejectedScanIds.append(scan.id)
            }
        }

        return MediaStagingPreparation(
            uploadItems: uploadItems,
            uploadFiles: uploadFiles,
            rejectedScanIds: rejectedScanIds
        )
    }

    nonisolated func selectUploadBatch(
        from scans: [PendingScanPayload]
    ) -> [PendingScanPayload] {
        let maxPresignedURLsPerRequest = MediaStagingContract.maxUploadItemsPerRequest
        var selected: [PendingScanPayload] = []
        selected.reserveCapacity(MerianConfig.uploadBatchSize)
        var uploadItemCount = 0

        for scan in scans {
            guard selected.count < MerianConfig.uploadBatchSize else { break }
            let scanUploadCount = scan.localUploadPaths.count
            guard scanUploadCount > 0 else { continue }
            if uploadItemCount + scanUploadCount > maxPresignedURLsPerRequest {
                // Let the normal media-contract validator quarantine one
                // oversized head row, but do not let a later non-fitting row
                // prevent still-smaller work from filling the batch.
                if selected.isEmpty {
                    selected.append(scan)
                    break
                }
                continue
            }
            selected.append(scan)
            uploadItemCount += scanUploadCount
            if uploadItemCount >= maxPresignedURLsPerRequest {
                break
            }
        }

        return selected
    }
}
