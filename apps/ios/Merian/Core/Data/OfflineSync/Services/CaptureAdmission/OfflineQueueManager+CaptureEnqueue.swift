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
        let resolvedScanId = (scanId ?? UUID().uuidString).lowercased()
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
        let visualMediaItemsJSON: String?
        do {
            if let visualMediaItems {
                guard visualMediaItems.count == imageDatas.count,
                      visualMediaItems.allSatisfy(\.isValidEvidence) else {
                    onQueued?(false)
                    return
                }
                guard let encoded = String(data: try JSONEncoder().encode(visualMediaItems), encoding: .utf8) else {
                    onQueued?(false)
                    return
                }
                visualMediaItemsJSON = encoded
            } else { visualMediaItemsJSON = nil }
        } catch {
            onQueued?(false)
            return
        }
        guard beginInitialCaptureAdmission(resolvedScanId) else {
            onQueued?(false)
            return
        }
        let notifyQueued = onQueued
        // This callback retains the owner through file persistence and releases
        // the admission before callbacks can attempt another submission.
        let finishQueued: (@MainActor @Sendable (Bool) -> Void)? = { [self] accepted in
            inFlightInitialCaptureIDs.remove(resolvedScanId)
            notifyQueued?(accepted)
        }
        let initialFieldNotes = InitialFieldNotesSeed.make(
            contexts: timeline.compactMap { if case .description(let value) = $0 { value } else { nil } }
        )
        guard let funding = CaptureFundingAdmission.claimFundingAdmission(
            scanId: resolvedScanId,
            timeline: timeline
        ) else {
            if let finishQueued { finishQueued(false) }
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueCapture: storage pressure blocked queue insert scanId=\(resolvedScanId, privacy: .public) bytes=\(estimatedPayloadBytes, privacy: .public)")
            if let finishQueued {
                finishQueued(false)
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
                    if let finishQueued { finishQueued(false) }
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
                        CaptureFundingAdmission.rollbackFundingAdmission(funding)
                    }
                    MerianLog.data.error("enqueueCapture: failed to persist the full staged image set — scan will not be queued.")
                    if let finishQueued {
                        await MainActor.run { finishQueued(false) }
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
                            CaptureFundingAdmission.rollbackFundingAdmission(funding)
                        }
                        MerianLog.data.error("enqueueCapture: failed to persist the full display media set — scan will not be queued.")
                        if let finishQueued {
                            await MainActor.run { finishQueued(false) }
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
                let didQueue = await self.insertAndPersistRecord(
                    scanId: resolvedScanId,
                    fileURLs: fileURLs,
                    capturedMediaJSON: capturedMediaJSON,
                    initialFieldNotes: initialFieldNotes,
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
                    finishQueued?(didQueue)
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
                    CaptureFundingAdmission.rollbackFundingAdmission(funding)
                }
                if let finishQueued {
                    await MainActor.run { finishQueued(false) }
                }
            }
        }
    }

    // MARK: - Enqueue Helpers

    func beginInitialCaptureAdmission(_ scanID: String) -> Bool {
        guard !inFlightInitialCaptureIDs.contains(scanID), isNewCaptureIdentity(scanID) else { return false }
        return inFlightInitialCaptureIDs.insert(scanID).inserted
    }

    private func isNewCaptureIdentity(_ scanID: String) -> Bool {
        guard let modelContext else { return false }
        do {
            return try modelContext.fetchCount(FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanID })) == 0
                && modelContext.fetchCount(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanID })) == 0
        } catch { return false }
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
        let resolvedScanId = (scanId ?? UUID().uuidString).lowercased()
        #if DEBUG && targetEnvironment(simulator)
        if let comparison = telemetry.debugReplayProfile?.comparison {
            guard resolvedScanId == comparison.scanId, foregroundInferenceGeneration != nil,
                  DebugAudioComparisonAdmission.isAvailable(scanId: resolvedScanId, context: modelContext) else { return false }
        }
        #endif
        guard beginInitialCaptureAdmission(resolvedScanId) else { return false }
        defer { inFlightInitialCaptureIDs.remove(resolvedScanId) }
        let initialFieldNotes = InitialFieldNotesSeed.make(
            contexts: timeline.compactMap { if case .description(let value) = $0 { value } else { nil } }
        )
        guard let funding = CaptureFundingAdmission.claimFundingAdmission(
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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

        let records = CaptureQueueInitialRecords(scanId: resolvedScanId, timestamp: Date(),
            capturedMediaJSON: capturedMediaJSON, initialFieldNotes: initialFieldNotes,
            inferenceImagePaths: [], visualMediaItemsJSON: nil, preferredGoal: nil,
            telemetry: telemetry, blurScore: nil, funding: funding,
            foregroundInferenceGeneration: admittedForegroundGeneration,
            mode: .nonVisual(hasUploadableMedia: hasUploadableMedia))
        let scan = records.scan

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
                metadataJSON: records.jobMetadata
            )
            modelContext.insert(records.queuedEvent(jobID: job.id))
        } catch {
            modelContext.rollback()
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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
        initialFieldNotes: String?,
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
            return false
        }

        guard captureLibraryAdmission(funding.accountId) else {
            await cleanupPersistedCaptureFiles(fileURLs)
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
            return false
        }
        // File writes yielded the actor. A durable identity that appeared in
        // the meantime owns its mutable note; never upsert/reseed it. Funding
        // is keyed by the same ID: collision or lookup uncertainty cannot prove
        // this reservation is ours to refund. Retain it for reconciliation.
        guard isNewCaptureIdentity(scanId) else {
            await cleanupPersistedCaptureFiles(fileURLs)
            return false
        }
        let records = CaptureQueueInitialRecords(scanId: scanId, timestamp: timestamp,
            capturedMediaJSON: capturedMediaJSON, initialFieldNotes: initialFieldNotes,
            inferenceImagePaths: inferenceImagePaths, visualMediaItemsJSON: visualMediaItemsJSON,
            preferredGoal: preferredGoal, telemetry: telemetry, blurScore: blurScore,
            funding: funding, foregroundInferenceGeneration: foregroundInferenceGeneration)
        let scan = records.scan

        modelContext.insert(scan)
        if let goal = records.goalHint { modelContext.insert(goal) }
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
                metadataJSON: records.jobMetadata
            )
            modelContext.insert(records.queuedEvent(jobID: job.id))
        } catch {
            modelContext.rollback()
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
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
            CaptureFundingAdmission.rollbackFundingAdmission(funding)
            MerianLog.data.error("enqueueCapture: context.save() failed — scan record lost, cleaning up image footprints: \(error, privacy: .private)")
            await cleanupPersistedCaptureFiles(fileURLs)
            return false
        }
    }
}
