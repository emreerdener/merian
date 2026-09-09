import Foundation
import SwiftData

// MARK: - Live Capture Lifecycle

extension OfflineQueueManager {

    /// Releases a single live scan's upload hold. An inference generation makes
    /// delayed body-sent and fail-safe callbacks compare before releasing a hold
    /// that may now belong to a replacement attempt.
    func releaseDeferredLiveUpload(
        scanId: String,
        foregroundInferenceGeneration: UUID? = nil,
        reason: String
    ) {
        if let foregroundInferenceGeneration {
            guard foregroundInferenceGenerations[scanId]
                    == foregroundInferenceGeneration else {
                return
            }
        }
        guard deferredLiveUploadScanIds.remove(scanId) != nil else { return }
        MerianLog.data.debug(
            "releaseDeferredLiveUpload: scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public)"
        )
        syncPendingScans()
    }

    func releaseAllDeferredLiveUploads(reason: String) {
        guard !deferredLiveUploadScanIds.isEmpty else { return }
        let scanIds = deferredLiveUploadScanIds
        deferredLiveUploadScanIds.removeAll()
        MerianLog.data.debug(
            "releaseAllDeferredLiveUploads: count=\(scanIds.count, privacy: .public) reason=\(reason, privacy: .public)"
        )
        syncPendingScans()
    }

    func isForegroundInferenceGenerationCurrent(
        scanId: String,
        generation: UUID
    ) -> Bool {
        foregroundInferenceGenerations[scanId] == generation
    }

    /// Atomically consumes a queue-backed foreground generation for one provider
    /// pipeline. This ownership lives with the queue rather than an engine
    /// instance, so duplicate submissions cannot reuse a callback-equivalent
    /// UUID.
    func canStartForegroundInference(
        scanId: String,
        generation: UUID
    ) -> Bool {
        EntitlementManager.shared.fundingAllowsForegroundInference(
            scanId: scanId
        ) &&
            foregroundInferenceGenerations[scanId] == generation &&
            startedForegroundInferenceGenerations[scanId] == nil &&
            !foregroundInferenceRetirementTasks.isOwned(
                scanId,
                by: generation
            )
    }

    func isForegroundInferenceAttemptCurrent(
        scanId: String,
        generation: UUID
    ) -> Bool {
        foregroundInferenceGenerations[scanId] == generation &&
            startedForegroundInferenceGenerations[scanId] == generation &&
            !foregroundInferenceRetirementTasks.isOwned(
                scanId,
                by: generation
            )
    }

    func claimForegroundInferenceStart(
        scanId: String,
        generation: UUID
    ) -> Bool {
        guard canStartForegroundInference(
            scanId: scanId,
            generation: generation
        ) else {
            return false
        }
        startedForegroundInferenceGenerations[scanId] = generation
        return true
    }

    /// Synchronously retires a foreground UUID, then retries its durable handoff
    /// with capped backoff. Registering the task before yielding closes the
    /// cancellation-to-handoff window for every caller, including pre-provider
    /// capture exits that have no active `InferenceEngine` task.
    func retireForegroundInference(
        scanId: String,
        generation: UUID,
        resumeBackground: Bool,
        reason: String
    ) {
        guard foregroundInferenceGenerations[scanId] == generation,
              !foregroundInferenceRetirementTasks.isOwned(
                  scanId,
                  by: generation
              ) else {
            return
        }

        foregroundInferenceRetirementTasks.replace(
            for: scanId,
            ownerGeneration: generation
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var retryDelay = Duration.milliseconds(250)
                defer {
                    self.foregroundInferenceRetirementTasks.clearIfCurrent(
                        scanId,
                        token: token
                    )
                }

                while !Task.isCancelled,
                      self.foregroundInferenceRetirementTasks.isCurrent(
                          scanId,
                          token: token,
                          ownerGeneration: generation
                      ),
                      self.foregroundInferenceGenerations[scanId]
                        == generation {
                    let didEnd = await self.endForegroundInference(
                        scanId: scanId,
                        generation: generation,
                        resumeBackground: resumeBackground,
                        reason: reason
                    )
                    guard !didEnd,
                          self.foregroundInferenceRetirementTasks.isCurrent(
                              scanId,
                              token: token,
                              ownerGeneration: generation
                          ),
                          self.foregroundInferenceGenerations[scanId]
                            == generation else {
                        break
                    }

                    // Keep the UUID retired while a transient SwiftData
                    // fetch/save failure is retried. Reusing it would admit
                    // delayed callbacks, while abandoning it would suppress
                    // recovery indefinitely.
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, .seconds(5))
                }
            }
        }
    }

    /// Releases only the expected foreground owner. The durable generation is
    /// cleared under the same per-scan coordinator used by background claims and
    /// live-result persistence, establishing one linear handoff point.
    @discardableResult
    func endForegroundInference(
        scanId: String,
        generation: UUID,
        resumeBackground: Bool,
        reason: String
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard foregroundInferenceGenerations[scanId] == generation else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return false
        }

        var didClearDurableOwner = true
        if let context = modelContext {
            let jobId = Self.scanIngestionJobId(scanId: scanId)
            do {
                if let job = try context.fetchOfflineJob(id: jobId) {
                    if InferenceGenerationMetadataContract.matches(
                        generation,
                        in: job.metadataJSON
                    ) {
                        job.metadataJSON =
                            InferenceGenerationMetadataContract.removing(
                                generation,
                                from: job.metadataJSON
                            )
                        job.updatedAt = Date()
                        do {
                            try context.save()
                        } catch {
                            context.rollback()
                            didClearDurableOwner = false
                            MerianLog.data.error(
                                "endForegroundInference: durable handoff failed scanId=\(scanId, privacy: .public) error=\(error, privacy: .private)"
                            )
                        }
                    } else if InferenceGenerationMetadataContract.generation(
                        in: job.metadataJSON
                    ) != nil {
                        didClearDurableOwner = false
                    }
                    // A different durable generation has already replaced this
                    // owner. Never clear its metadata.
                }
            } catch {
                didClearDurableOwner = false
                MerianLog.data.error(
                    "endForegroundInference: ownership fetch failed scanId=\(scanId, privacy: .public) error=\(error, privacy: .private)"
                )
            }
        } else {
            didClearDurableOwner = false
        }

        if didClearDurableOwner {
            foregroundInferenceGenerations[scanId] = nil
            if startedForegroundInferenceGenerations[scanId] == generation {
                startedForegroundInferenceGenerations[scanId] = nil
            }
        }
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)

        guard didClearDurableOwner else { return false }
        MerianLog.data.debug(
            "endForegroundInference: scanId=\(scanId, privacy: .public) resume=\(resumeBackground, privacy: .public) reason=\(reason, privacy: .public)"
        )
        if resumeBackground {
            syncPendingScans()
            replayInferenceForUploadedScans()
        }
        return true
    }

    func releaseAllForegroundInferenceClaims(reason: String) {
        let claims = foregroundInferenceGenerations
        guard !claims.isEmpty else { return }
        MerianLog.data.debug(
            "releaseAllForegroundInferenceClaims: count=\(claims.count, privacy: .public) reason=\(reason, privacy: .public)"
        )
        for (scanId, generation) in claims {
            retireForegroundInference(
                scanId: scanId,
                generation: generation,
                resumeBackground: true,
                reason: reason
            )
        }
    }

    /// Merges late WeatherKit/geocoder values into the durable queue record so
    /// an offline replay carries the same context even if the live request fails.
    func updateDeferredContext(scanId: String, telemetry: CaptureTelemetry) {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan?
        do {
            scan = try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.error(
                "updateDeferredContext: fetch failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return
        }
        guard let scan else { return }

        scan.gpsElevation = telemetry.gpsElevation ?? scan.gpsElevation
        scan.weatherCondition = telemetry.weatherCondition ?? scan.weatherCondition
        scan.weatherTemperatureF = telemetry.weatherTemperatureF ?? scan.weatherTemperatureF
        scan.locationName = telemetry.locationName ?? scan.locationName
        scan.queueUpdatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "updateDeferredContext: save failed scanId=\(scanId, privacy: .public) error=\(error, privacy: .private)"
            )
        }
    }
}
