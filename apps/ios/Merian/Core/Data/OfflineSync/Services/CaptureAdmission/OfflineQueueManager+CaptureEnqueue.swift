import Foundation
import SwiftData

// MARK: - Capture Admission

extension OfflineQueueManager {

    // MARK: - Capture Enqueue

    /// Persists queue-owned media copies and the durable scan before acknowledging acceptance.
    /// Source files remain caller-owned on failure. A successful `onAdmission` returns the
    /// mapped timeline for foreground inference; recovery continues with the same scan ID.
    /// Extended background time protects writes during app suspension. Live inference can
    /// defer background dispatch until its inline request body has been sent.
    func enqueueCapture(
        imageDatas: [Data],
        displayImageDatas: [Data]? = nil,
        audioFilePaths: [String] = [],
        videoFilePaths: [String] = [],
        telemetry: CaptureTelemetry,
        blurScore: Double? = nil,
        scanId: String? = nil,
        observationContexts: [ObservationContext] = [],
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        preferredGoal: FieldTripPreferredGoal? = nil,
        captureDate: Date = Date(),
        foregroundInferenceGeneration: UUID? = nil,
        startSyncImmediately: Bool = true,
        onQueued: (@MainActor @Sendable (Bool) -> Void)? = nil,
        onAdmission: (@MainActor @Sendable ([CaptureSubmissionMediaItem]?) -> Void)? = nil
    ) {
        guard captureLibraryAdmission(nil) else {
            onQueued?(false)
            onAdmission?(nil)
            return
        }
        let legacyOnQueued = onQueued
        let onQueued: (@MainActor @Sendable (Bool) -> Void)? = { accepted in
            legacyOnQueued?(accepted)
            if !accepted { onAdmission?(nil) }
        }
        guard audioFilePaths.allSatisfy(
            InferenceAudioPreparer.isQueueEligibleInferenceAudioPath
        ) else {
            MerianLog.data.error(
                "enqueueCapture: rejected an invalid local WAV inference source."
            )
            if let onQueued { onQueued(false) }
            return
        }
        let resolvedScanId = scanId ?? UUID().uuidString.lowercased()
        let documentsDirectory = URL.documentsDirectory
        let resolvedDisplayImageDatas = displayImageDatas ?? imageDatas
        MerianLog.data.debug(
            "enqueueCapture: requested scanId=\(resolvedScanId, privacy: .public) inferenceImages=\(imageDatas.count, privacy: .public) displayImages=\(resolvedDisplayImageDatas.count, privacy: .public) bytes=\(imageDatas.reduce(0) { $0 + $1.count }, privacy: .public)"
        )
        let timeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: resolvedDisplayImageDatas.count,
            observationContexts: observationContexts,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths
        )
        guard let funding = claimFundingAdmission(
            scanId: resolvedScanId,
            timeline: timeline
        ) else {
            if let onQueued { onQueued(false) }
            return
        }
        let admittedForegroundGeneration = funding.allowsForegroundInference
            ? foregroundInferenceGeneration
            : nil
        let displayBytes = displayImageDatas.map { $0.reduce(0) { $0 + $1.count } } ?? 0
        let estimatedPayloadBytes = Int64(imageDatas.reduce(0) { $0 + $1.count })
            + Int64(displayBytes)
            + OfflineQueueStoragePolicy.estimatedBytes(
                for: audioFilePaths + videoFilePaths
            )
        guard OfflineQueueStoragePolicy.canAdmitNewPayload(estimatedBytes: estimatedPayloadBytes) else {
            rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueCapture: storage pressure blocked queue insert scanId=\(resolvedScanId, privacy: .public) bytes=\(estimatedPayloadBytes, privacy: .public)")
            if let onQueued {
                onQueued(false)
            }
            return
        }

        BackgroundTaskWrapper.execute(name: "OfflineQueueCaptureWrite", priority: .userInitiated) { [weak self] _ in
            guard let self else {
                await MainActor.run {
                    if funding.source == .immediateFlash ||
                        funding.source == .deferredFlash {
                        UsageManager.shared.refundScan(scanId: funding.scanId)
                    }
                    EntitlementManager.shared
                        .releaseFundingAfterProvenLocalFailure(
                            scanId: funding.scanId
                        )
                    if let onQueued { onQueued(false) }
                }
                return
            }
            var fileURLs: [URL] = []
            do {
                let inferenceFileNames = await FileIOActor.shared.writeTemporaryImages(imageDatas: imageDatas)
                fileURLs.append(contentsOf: inferenceFileNames.map { documentsDirectory.appendingPathComponent($0) })
                guard inferenceFileNames.count == imageDatas.count else {
                    await self.cleanupPersistedCaptureFiles(fileURLs)
                    await MainActor.run {
                        self.rollbackFundingAdmission(funding)
                    }
                    MerianLog.data.error("enqueueCapture: failed to persist the full staged image set — scan will not be queued.")
                    if let onQueued {
                        await MainActor.run { onQueued(false) }
                    }
                    return
                }

                let displayFileNames: [String]
                if displayImageDatas == nil {
                    displayFileNames = inferenceFileNames
                } else {
                    let persistedDisplayNames = await FileIOActor.shared.writeTemporaryImages(imageDatas: resolvedDisplayImageDatas)
                    fileURLs.append(contentsOf: persistedDisplayNames.map { documentsDirectory.appendingPathComponent($0) })
                    guard persistedDisplayNames.count == resolvedDisplayImageDatas.count else {
                        await self.cleanupPersistedCaptureFiles(fileURLs)
                        await MainActor.run {
                            self.rollbackFundingAdmission(funding)
                        }
                        MerianLog.data.error("enqueueCapture: failed to persist the full display media set — scan will not be queued.")
                        if let onQueued {
                            await MainActor.run { onQueued(false) }
                        }
                        return
                    }
                    displayFileNames = persistedDisplayNames
                }

                MerianLog.data.debug(
                    "enqueueCapture: persisted temp files scanId=\(resolvedScanId, privacy: .public) inferenceFiles=\(inferenceFileNames.joined(separator: ","), privacy: .private) displayFiles=\(displayFileNames.joined(separator: ","), privacy: .private)"
                )
                let persistedAudioNamesBySourcePath = try OfflineCaptureFileStore.persistFiles(
                    audioFilePaths,
                    documentsDirectory: documentsDirectory
                )
                fileURLs.append(contentsOf: persistedAudioNamesBySourcePath.values.map { documentsDirectory.appendingPathComponent($0) })
                let persistedVideoNamesBySourcePath = try OfflineCaptureFileStore.persistFiles(
                    videoFilePaths,
                    documentsDirectory: documentsDirectory
                )
                fileURLs.append(contentsOf: persistedVideoNamesBySourcePath.values.map { documentsDirectory.appendingPathComponent($0) })
                let acceptedTimeline = try OfflineCaptureFileStore.acceptedTimeline(
                    timeline, audio: persistedAudioNamesBySourcePath,
                    video: persistedVideoNamesBySourcePath, documentsDirectory: documentsDirectory
                )
                let capturedMediaJSON = OfflineCaptureFileStore.makeCapturedMediaJSON(
                    mediaTimeline: timeline,
                    imageFileNames: displayFileNames,
                    persistedAudioNamesBySourcePath: persistedAudioNamesBySourcePath,
                    persistedVideoNamesBySourcePath: persistedVideoNamesBySourcePath
                )
                let visualMediaItemsJSON: String?
                if let visualMediaItems,
                   visualMediaItems.count == inferenceFileNames.count,
                   let encoded = try? JSONEncoder().encode(visualMediaItems) {
                    visualMediaItemsJSON = String(data: encoded, encoding: .utf8)
                } else {
                    visualMediaItemsJSON = nil
                }

                let didQueue = await self.insertAndPersistRecord(
                    scanId: resolvedScanId,
                    fileURLs: fileURLs,
                    capturedMediaJSON: capturedMediaJSON,
                    inferenceImagePaths: inferenceFileNames,
                    visualMediaItemsJSON: visualMediaItemsJSON,
                    preferredGoal: preferredGoal,
                    telemetry: telemetry,
                    blurScore: blurScore,
                    timestamp: captureDate,
                    funding: funding,
                    foregroundInferenceGeneration: admittedForegroundGeneration,
                    startSyncImmediately: startSyncImmediately
                )
                await MainActor.run {
                    if didQueue { onAdmission?(acceptedTimeline) }
                    onQueued?(didQueue)
                }
                MerianLog.data.debug(
                    "enqueueCapture: insert complete scanId=\(resolvedScanId, privacy: .public) didQueue=\(didQueue, privacy: .public)"
                )
            } catch {
                MerianLog.data.error("enqueueCapture: image write to disk failed — scan will not be queued: \(error, privacy: .private)")
                if !fileURLs.isEmpty {
                    await self.cleanupPersistedCaptureFiles(fileURLs)
                }
                await MainActor.run {
                    self.rollbackFundingAdmission(funding)
                }
                if let onQueued {
                    await MainActor.run { onQueued(false) }
                }
            }
        }
    }

    // MARK: - Enqueue Helpers

    private func claimFundingAdmission(
        scanId: String,
        timeline: [CaptureSubmissionMediaItem]
    ) -> ScanFundingReservation? {
        guard let funding = EntitlementManager.shared.claimFunding(
            scanId: scanId,
            flashFallbackEligible: isFlashFallbackEligible(timeline)
        ) else {
            UsageManager.shared.showPaywall = true
            return nil
        }
        if funding.source == .immediateFlash ||
            funding.source == .deferredFlash {
            guard UsageManager.shared.canPerformScan(isProActive: false) else {
                EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
                    scanId: funding.scanId
                )
                UsageManager.shared.showPaywall = true
                return nil
            }
            UsageManager.shared.consumeScan(scanId: funding.scanId)
        }
        return funding
    }

    private func rollbackFundingAdmission(_ funding: ScanFundingReservation) {
        if funding.source == .immediateFlash ||
            funding.source == .deferredFlash {
            UsageManager.shared.refundScan(scanId: funding.scanId)
        }
        EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
            scanId: funding.scanId
        )
    }

    private func isFlashFallbackEligible(
        _ timeline: [CaptureSubmissionMediaItem]
    ) -> Bool {
        CaptureSubmissionPolicy.isFlashFallbackEligible(timeline)
    }

    private func cleanupPersistedCaptureFiles(_ urls: [URL]) async {
        await FileIOActor.shared.deleteFiles(at: urls.map(\.path))
    }

    // MARK: - Non-Visual Capture

    @MainActor
    @discardableResult
    func enqueueNonVisualCapture(
        audioFileNames: [String],
        observationContexts: [ObservationContext],
        videoFilePaths: [String] = [],
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        telemetry: CaptureTelemetry,
        scanId: String? = nil,
        foregroundInferenceGeneration: UUID? = nil,
        onAccepted: (([CaptureSubmissionMediaItem]) -> Void)? = nil
    ) -> Bool {
        guard captureLibraryAdmission(nil) else { return false }
        let filteredAudioFileNames = audioFileNames.filter { !$0.isEmpty }
        let filteredVideoFilePaths = videoFilePaths.filter { !$0.isEmpty }
        let filteredObservationContexts = observationContexts.filter { !$0.isEmpty }
        guard filteredAudioFileNames.allSatisfy(
            InferenceAudioPreparer.isQueueEligibleInferenceAudioPath
        ) else {
            MerianLog.data.error(
                "enqueueNonVisualCapture: rejected an invalid local WAV inference source."
            )
            return false
        }
        let timeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: 0,
            observationContexts: filteredObservationContexts,
            audioFilePaths: filteredAudioFileNames,
            videoFilePaths: filteredVideoFilePaths
        )

        guard !timeline.isEmpty else { return false }
        let resolvedScanId = scanId ?? UUID().uuidString.lowercased()
        #if DEBUG && targetEnvironment(simulator)
        if let comparison = telemetry.debugReplayProfile?.comparison {
            guard resolvedScanId == comparison.scanId, foregroundInferenceGeneration != nil,
                  DebugAudioComparisonAdmission.isAvailable(scanId: resolvedScanId, context: modelContext) else { return false }
        }
        #endif
        guard let funding = claimFundingAdmission(
            scanId: resolvedScanId,
            timeline: timeline
        ) else {
            return false
        }
        let admittedForegroundGeneration = funding.allowsForegroundInference
            ? foregroundInferenceGeneration
            : nil
        let estimatedPayloadBytes = OfflineQueueStoragePolicy.estimatedBytes(
            for: filteredAudioFileNames + filteredVideoFilePaths
        )
        guard OfflineQueueStoragePolicy.canAdmitNewPayload(estimatedBytes: estimatedPayloadBytes) else {
            rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueNonVisualCapture: storage pressure blocked queue insert bytes=\(estimatedPayloadBytes, privacy: .public)")
            return false
        }

        let persistedAudioNamesBySourcePath: [String: String]
        do {
            persistedAudioNamesBySourcePath = try OfflineCaptureFileStore.persistFiles(
                filteredAudioFileNames,
                documentsDirectory: URL.documentsDirectory
            )
        } catch {
            rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueNonVisualCapture: failed to persist audio file — scan not queued: \(error, privacy: .private)")
            return false
        }

        let persistedVideoNamesBySourcePath: [String: String]
        do {
            persistedVideoNamesBySourcePath = try OfflineCaptureFileStore.persistFiles(
                filteredVideoFilePaths,
                documentsDirectory: URL.documentsDirectory
            )
        } catch {
            MerianLog.data.error("enqueueNonVisualCapture: failed to persist video file — scan not queued: \(error, privacy: .private)")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
            }
            rollbackFundingAdmission(funding)
            return false
        }

        guard let modelContext else {
            MerianLog.data.error("enqueueNonVisualCapture: modelContext unavailable — scan not queued")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
            }
            for persistedVideoName in persistedVideoNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedVideoName))
            }
            rollbackFundingAdmission(funding)
            return false
        }

        let capturedMediaJSON = OfflineCaptureFileStore.makeCapturedMediaJSON(
            mediaTimeline: timeline,
            imageFileNames: [],
            persistedAudioNamesBySourcePath: persistedAudioNamesBySourcePath,
            persistedVideoNamesBySourcePath: persistedVideoNamesBySourcePath
        )
        let hasAudio = !persistedAudioNamesBySourcePath.isEmpty
        let hasUploadableMedia = hasAudio || !persistedVideoNamesBySourcePath.isEmpty

        let scan = OfflineQueuedScan(
            id: resolvedScanId,
            timestamp: Date(),
            capturedMediaJSON: capturedMediaJSON,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            blurScore: nil,
            subjectDistanceInMeters: nil,
            locationName: telemetry.locationName,
            isFlashFired: nil,
            cameraPitchDegrees: nil,
            compassHeading: nil,
            relativeHumidity: nil,
            uvIndex: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) },
            scanState: hasUploadableMedia ? .pending : .staged,
            stagedR2Keys: []
        )
        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
            scan.replaceCapturedMedia(with: items)
        }

        modelContext.insert(scan)
        do {
            let job = try modelContext.ensureOfflineJobRecord(
                id: Self.scanIngestionJobId(scanId: resolvedScanId),
                kind: .scanIngestion,
                subjectId: resolvedScanId,
                priority: hasUploadableMedia ? 100 : 120,
                approximateBytes: OfflineQueueStoragePolicy.approximateBytes(
                    for: persistedAudioNamesBySourcePath.values.map {
                        URL.documentsDirectory.appendingPathComponent($0)
                    } + persistedVideoNamesBySourcePath.values.map {
                        URL.documentsDirectory.appendingPathComponent($0)
                    }
                ),
                requiresUnconstrainedNetwork: !persistedVideoNamesBySourcePath.isEmpty,
                allowsCellular: persistedVideoNamesBySourcePath.isEmpty,
                metadataJSON: OfflineScanJobMetadataContract.json(
                    generation: admittedForegroundGeneration,
                    funding: funding
                )
            )
            modelContext.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: resolvedScanId,
                kind: .queued,
                message: "Queued non-visual scan for sync."
            ))
        } catch {
            modelContext.rollback()
            rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueNonVisualCapture: failed to create offline job: \(error, privacy: .private)")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(
                    at: URL.documentsDirectory.appendingPathComponent(
                        persistedAudioName
                    )
                )
            }
            for persistedVideoName in persistedVideoNamesBySourcePath.values {
                try? FileManager.default.removeItem(
                    at: URL.documentsDirectory.appendingPathComponent(
                        persistedVideoName
                    )
                )
            }
            return false
        }
        do {
            let acceptedTimeline = try OfflineCaptureFileStore.acceptedTimeline(
                timeline, audio: persistedAudioNamesBySourcePath,
                video: persistedVideoNamesBySourcePath, documentsDirectory: .documentsDirectory
            )
            try modelContext.save()
            onAccepted?(acceptedTimeline)
            if let admittedForegroundGeneration {
                foregroundInferenceRetirementTasks.cancel(resolvedScanId)
                startedForegroundInferenceGenerations[resolvedScanId] = nil
                foregroundInferenceGenerations[resolvedScanId] =
                    admittedForegroundGeneration
            }
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
            if hasUploadableMedia && funding.allowsDispatch {
                syncPendingScans()
            } else if isOnline && funding.allowsDispatch {
                replayInferenceForUploadedScans()
            }
            return true
        } catch {
            modelContext.rollback()
            rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueNonVisualCapture: context.save() failed: \(error, privacy: .private)")
            for persistedAudioName in persistedAudioNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedAudioName))
            }
            for persistedVideoName in persistedVideoNamesBySourcePath.values {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(persistedVideoName))
            }
            return false
        }
    }

    // MARK: - Durable Persistence

    @MainActor
    private func insertAndPersistRecord(
        scanId: String,
        fileURLs: [URL],
        capturedMediaJSON: String?,
        inferenceImagePaths: [String],
        visualMediaItemsJSON: String?,
        preferredGoal: FieldTripPreferredGoal?,
        telemetry: CaptureTelemetry,
        blurScore: Double?,
        timestamp: Date,
        funding: ScanFundingReservation,
        foregroundInferenceGeneration: UUID?,
        startSyncImmediately: Bool
    ) async -> Bool {
        // Enforce quota at enqueue time so every scan that enters the queue is guaranteed to upload.
        // Consuming here (not at upload time) prevents silent stalls when syncPendingScans fires
        // after the experience was already granted to the user.
        guard let modelContext else {
            MerianLog.data.error(
                "insertAndPersistRecord: modelContext missing scanId=\(scanId, privacy: .public)"
            )
            await cleanupPersistedCaptureFiles(fileURLs)
            rollbackFundingAdmission(funding)
            return false
        }

        guard captureLibraryAdmission(funding.accountId) else {
            await cleanupPersistedCaptureFiles(fileURLs)
            rollbackFundingAdmission(funding)
            return false
        }
        let scan = OfflineQueuedScan(
            id: scanId,
            timestamp: timestamp,
            capturedMediaJSON: capturedMediaJSON,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            blurScore: blurScore,
            subjectDistanceInMeters: telemetry.subjectDistanceInMeters,
            locationName: telemetry.locationName,
            isFlashFired: nil,
            cameraPitchDegrees: nil,
            compassHeading: nil,
            relativeHumidity: nil,
            uvIndex: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) },
            scanState: .pending,
            inferenceImagePaths: inferenceImagePaths.isEmpty ? nil : inferenceImagePaths,
            visualMediaItemsJSON: visualMediaItemsJSON
        )
        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
            scan.replaceCapturedMedia(with: items)
        }

        modelContext.insert(scan)
        if let preferredGoal {
            modelContext.insert(ActiveOfflineQueuedScanGoalHint(
                scanId: scanId,
                userFieldTripId: preferredGoal.userFieldTripId,
                itemId: preferredGoal.itemId
            ))
        }
        do {
            let job = try modelContext.ensureOfflineJobRecord(
                id: Self.scanIngestionJobId(scanId: scanId),
                kind: .scanIngestion,
                subjectId: scanId,
                priority: 100,
                approximateBytes: OfflineQueueStoragePolicy.approximateBytes(
                    for: fileURLs
                ),
                requiresUnconstrainedNetwork: scan.capturedMediaSnapshot.videoPaths.isEmpty == false,
                allowsCellular: scan.capturedMediaSnapshot.videoPaths.isEmpty,
                metadataJSON: OfflineScanJobMetadataContract.json(
                    generation: foregroundInferenceGeneration,
                    funding: funding
                )
            )
            modelContext.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .queued,
                message: "Queued scan for upload."
            ))
        } catch {
            modelContext.rollback()
            rollbackFundingAdmission(funding)
            await cleanupPersistedCaptureFiles(fileURLs)
            MerianLog.data.error("insertAndPersistRecord: failed to create offline job: \(error, privacy: .private)")
            return false
        }

        do {
            try modelContext.save()
            if let foregroundInferenceGeneration {
                foregroundInferenceRetirementTasks.cancel(scanId)
                startedForegroundInferenceGenerations[scanId] = nil
                foregroundInferenceGenerations[scanId] =
                    foregroundInferenceGeneration
            }
            updateUnsyncedItemCount()
            AppTelemetry.trackOfflineQueued()
            MerianLog.data.debug(
                "insertAndPersistRecord: saved queue scanId=\(scanId, privacy: .public) state=pending images=\(fileURLs.count, privacy: .public)"
            )
            if startSyncImmediately && funding.allowsDispatch {
                syncPendingScans()
            } else if funding.allowsDispatch {
                deferredLiveUploadScanIds.insert(scanId)
                MerianLog.data.debug(
                    "insertAndPersistRecord: deferring duplicate live upload scanId=\(scanId, privacy: .public)"
                )
            }
            return true
        } catch {
            modelContext.rollback()
            rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueCapture: context.save() failed — scan record lost, cleaning up image footprints: \(error, privacy: .private)")
            await cleanupPersistedCaptureFiles(fileURLs)
            return false
        }
    }
}
