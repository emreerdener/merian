import Foundation
import SwiftData

// MARK: - Sync Operations

extension OfflineQueueManager {

    // MARK: - Cloud Deletions

    /// Drains the `PendingCloudDeletionTask` queue, calling the delete Edge function for each record.
    ///
    /// A task is removed only after an explicitly validated success response.
    /// Authentication, malformed-response, transport, and server errors all
    /// retain the task for the next connectivity cycle.
    func syncPendingDeletions() async {
        guard isOnline, let context = modelContext else { return }
        guard !isCloudDeletionSyncing else { return }
        isCloudDeletionSyncing = true
        defer { isCloudDeletionSyncing = false }

        let pendingTasks: [PendingCloudDeletionTask]
        do {
            var descriptor = FetchDescriptor<PendingCloudDeletionTask>(sortBy: [SortDescriptor(\.timestamp)])
            descriptor.fetchLimit = 200
            pendingTasks = try context.fetch(descriptor)
        } catch {
            MerianLog.data.debug("syncPendingDeletions: fetch failed: \(error, privacy: .private)")
            return
        }

        guard !pendingTasks.isEmpty else { return }

        let now = Date()
        var didPrepareJob = false
        let runnableTasks = pendingTasks.filter { task in
            let job = ensureCloudDeletionJob(scanId: task.scanId, context: context)
            if job?.created == true {
                didPrepareJob = true
            }
            guard let record = job?.record else { return true }
            if Self.cloudDeletionStatusRequiresRecovery(record.status) {
                // PendingCloudDeletionTask is the durable source of truth.
                // Older builds could pause an erasure permanently after the
                // generic retry budget, while complete/cancelled here would
                // contradict the still-present task. Heal every such state
                // before applying its retry eligibility date.
                record.status = .pending
                record.updatedAt = now
                record.nextRunAt = nil
                didPrepareJob = true
            }
            guard isRunnableCloudDeletionStatus(record.statusRaw) else { return false }
            if let nextRunAt = record.nextRunAt, nextRunAt > now {
                return false
            }
            return true
        }

        if didPrepareJob {
            do {
                try context.save()
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: failed to prepare deletion jobs: \(error, privacy: .private)")
                return
            }
        }

        guard !runnableTasks.isEmpty else { return }

        for task in runnableTasks {
            if let job = ensureCloudDeletionJob(scanId: task.scanId, context: context)?.record {
                job.status = .running
                job.updatedAt = now
                job.lastAttemptAt = now
                job.nextRunAt = nil
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    scanId: task.scanId,
                    kind: .claimed,
                    message: "Cloud deletion started."
                ))
            }
        }

        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("syncPendingDeletions: failed to claim deletion jobs: \(error, privacy: .private)")
            return
        }

        // Fetch O(n) results using the batch dispatcher
        let scanIds = runnableTasks.map(\.scanId)
        let allResults = await dispatchDeleteBatches(scanIds: scanIds)

        // Build an O(1) lookup so the per-result loop below doesn't scan the full
        // pendingTasks array for each result (was O(n²) when the batch was large).
        let taskById = Dictionary(uniqueKeysWithValues: runnableTasks.map { ($0.scanId, $0) })
        var didMutate = false
        for (scanId, error) in allResults {
            guard let task = taskById[scanId] else { continue }
            if Self.cloudDeletionWasConfirmed(error: error) {
                MerianLog.data.debug("✅ Deleted \(scanId, privacy: .private) from Edge")
                context.delete(task)
                markCloudDeletionJob(scanId: scanId, success: true, error: nil, context: context)
                didMutate = true
            } else if let error {
                MerianLog.data.error("syncPendingDeletions: failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                markCloudDeletionJob(scanId: scanId, success: false, error: error, context: context)
                didMutate = true
            }
        }

        if didMutate {
            do {
                try context.save()
                OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: save failed: \(error, privacy: .private)")
            }
        }
    }

    /// No local error category proves remote erasure. In particular,
    /// `invalidResponse` can represent an auth/session failure or a malformed
    /// HTTP success body. Only a nil dispatch error means `deleteScan` decoded
    /// the Edge route's explicit `success: true` confirmation.
    static func cloudDeletionWasConfirmed(error: Error?) -> Bool {
        error == nil
    }

    /// A pending erasure cannot be cancelled or declared complete locally.
    /// These statuses came from an older exhausted retry budget or contradict
    /// the still-present durable task, so the next drain repairs them.
    static func cloudDeletionStatusRequiresRecovery(
        _ status: OfflineJobStatus
    ) -> Bool {
        switch status {
        case .needsAttention, .complete, .cancelled:
            true
        case .pending, .running, .waiting:
            false
        }
    }

    /// Cloud erasure retries never exhaust. The diagnostic attempt number is
    /// capped only so exponential delay remains bounded and corrupt persisted
    /// values cannot overflow.
    static func nextCloudDeletionRetryAttempt(after currentAttempt: Int) -> Int {
        let maximumAttempt = OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        let boundedAttempt = min(max(0, currentAttempt), maximumAttempt)
        return min(boundedAttempt + 1, maximumAttempt)
    }

    /// Fans out deletions in batches to prevent unbounded concurrent network requests.
    /// Without a cap, a user returning from a week offline could saturate the pool and trigger rate limits.
    ///
    /// Batch size is hardware-aware: 10 concurrent sockets is the normal-operation ceiling,
    /// but in Low Power Mode the baseband chip is already constrained by the OS. Dropping to 3
    /// limits peak antenna transmit power, avoiding the thermal spike that cascades to CPU
    /// throttling and visible UI lag during large backlog drains.
    private func dispatchDeleteBatches(scanIds: [String]) async -> [(String, Error?)] {
        let batchSize = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 10
        var allResults: [(String, Error?)] = []
        allResults.reserveCapacity(scanIds.count)

        for batchStart in stride(from: 0, to: scanIds.count, by: batchSize) {
            let batch = Array(scanIds[batchStart..<min(batchStart + batchSize, scanIds.count)])
            let batchResults: [(String, Error?)] = await withTaskGroup(of: (String, Error?).self) { group in
                for scanId in batch {
                    group.addTask {
                        do {
                            try await MerianNetworkClient.shared.deleteScan(scanId: scanId)
                            return (scanId, nil)
                        } catch {
                            return (scanId, error)
                        }
                    }
                }
                var collected: [(String, Error?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            allResults.append(contentsOf: batchResults)
        }
        return allResults
    }

    private func markCloudDeletionJob(scanId: String, success: Bool, error: Error?, context: ModelContext) {
        let jobId = "cloud-deletion:\(scanId)"
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = (try? context.fetch(descriptor))?.first else { return }
        job.updatedAt = Date()
        if success {
            job.status = .complete
            job.nextRunAt = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.lastHTTPStatus = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .completed,
                message: "Cloud deletion completed."
            ))
        } else {
            job.lastAttemptAt = Date()
            job.lastErrorMessage = error?.localizedDescription
            job.status = .waiting
            job.attemptCount = Self.nextCloudDeletionRetryAttempt(
                after: job.attemptCount
            )
            job.nextRunAt = Date().addingTimeInterval(
                OfflineQueueRetryPolicy.jitteredDelay(forAttempt: job.attemptCount)
            )
            job.lastErrorCode = "cloud_deletion_failed"
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .retryScheduled,
                message: error?.localizedDescription,
                errorCode: "cloud_deletion_failed"
            ))
        }
    }

    private func isRunnableCloudDeletionStatus(_ statusRaw: String) -> Bool {
        statusRaw == OfflineJobStatus.pending.rawValue ||
            statusRaw == OfflineJobStatus.waiting.rawValue ||
            statusRaw == OfflineJobStatus.running.rawValue
    }

    private func ensureCloudDeletionJob(
        scanId: String,
        context: ModelContext
    ) -> (record: OfflineJobRecord, created: Bool)? {
        let jobId = "cloud-deletion:\(scanId)"
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return (existing, false)
        }

        let record = OfflineJobRecord(
            id: jobId,
            kind: .cloudDeletion,
            subjectId: scanId,
            priority: 60
        )
        context.insert(record)
        context.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .queued,
            message: "Queued cloud deletion."
        ))
        return (record, true)
    }

    // MARK: - Uploads

    /// Fetches `.pending` scans and schedules background `PUT` uploads to Cloudflare R2 staging.
    ///
    /// Upload tasks are tracked by
    /// `MediaStagingContract.uploadTaskDescription(scanId:uploadIndex:syncGeneration:objectKey:)`.
    /// Scans are atomically transitioned to `.uploading` state before tasks are dispatched,
    /// so `syncPendingScans` never re-dispatches in-flight uploads after an app restart.
    /// Confirmed R2 keys are persisted on the record at upload completion (in URLSession delegate).
    ///
    /// Guards: expedition mode, connectivity, and an in-flight sync must all clear.
    func syncPendingScans() {
        MerianLog.data.debug(
            "syncPendingScans: requested isOnline=\(self.isOnline, privacy: .public) isSyncing=\(self.isSyncing, privacy: .public) unsynced=\(self.unsyncedItemsCount, privacy: .public)"
        )
        guard !hardwareOrchestrator.isExpeditionModeActive else {
            MerianLog.data.debug("syncPendingScans: skipped because expedition mode is active")
            return
        }
        guard isOnline else {
            MerianLog.data.debug("syncPendingScans: skipped because network is offline")
            return
        }
        guard !isCurrentNetworkConstrained else {
            MerianLog.data.debug("syncPendingScans: skipped because network is constrained")
            return
        }
        guard !isSyncing else {
            MerianLog.data.debug("syncPendingScans: skipped because a sync is already active")
            return
        }
        guard let container = modelContext?.container else {
            MerianLog.data.error("syncPendingScans: skipped because modelContext is nil")
            return
        }

        let generation = UUID()
        isSyncing = true
        syncGeneration = generation

        syncTask = BackgroundTaskWrapper.execute(
            name: "OfflineQueueSync",
            expirationHandler: { [weak self] in
                MerianLog.data.debug("OfflineQueueSync background task expired")
                Task { @MainActor [weak self] in
                    self?.expireUploadSync(generation: generation)
                }
            }
        ) { [weak self] _ in
            guard let self else { return }
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }

            let dbActor = await MainActor.run {
                self.resolvedQueueDbActor(container: container)
            }
            let scanData = await dbActor.fetchPendingScans(limit: MerianConfig.pendingScanFetchLimit)
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let session  = await MainActor.run { self.backgroundSession }
            let allowsLargeUploads = await MainActor.run { self.allowsLargeQueuedUploadsOnCurrentNetwork }
            let forcedLargeUploadIds = await MainActor.run { self.userRequestedLargeUploadScanIds }
            let deferredLiveUploadIds = await MainActor.run { self.deferredLiveUploadScanIds }
            let eligibleScanData = scanData.filter { scan in
                !deferredLiveUploadIds.contains(scan.id) &&
                    (allowsLargeUploads || scan.localVideoPaths.isEmpty || forcedLargeUploadIds.contains(scan.id))
            }

            let filteredScans = self.selectUploadBatch(from: eligibleScanData)
            MerianLog.data.debug(
                "syncPendingScans: fetched pending=\(scanData.count, privacy: .public) eligible=\(eligibleScanData.count, privacy: .public) selected=\(filteredScans.count, privacy: .public) largeUploads=\(allowsLargeUploads, privacy: .public)"
            )

            guard !filteredScans.isEmpty else {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
                return
            }

            await MainActor.run {
                guard self.isCurrentUploadSync(generation) else { return }
                SyncStateManager.shared.beginSync(
                    itemCount: filteredScans.count,
                    generation: generation
                )
            }

            let stagingUserId = await self.currentMediaStagingUserId()
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let preparation = self.prepareUploadItems(from: filteredScans, userId: stagingUserId)

            if !preparation.rejectedScanIds.isEmpty {
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation) else { return }
                    for scanId in preparation.rejectedScanIds {
                        self.softDeleteQueuedScan(
                            scanId: scanId,
                            reason: "Queued media is missing, invalid, or exceeds the upload limit.",
                            errorCode: "queued_media_invalid"
                        )
                    }
                }
            }

            let uploadItems = preparation.uploadItems
            MerianLog.data.debug(
                "syncPendingScans: prepared uploadItems=\(uploadItems.count, privacy: .public) rejected=\(preparation.rejectedScanIds.count, privacy: .public)"
            )

            guard !uploadItems.isEmpty else {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
                return
            }

            let candidateUploadScanIds = Set(uploadItems.map(\.scanId))
            await MainActor.run {
                guard self.isCurrentUploadSync(generation) else { return }
                self.trackUploadPreparation(
                    scanIds: candidateUploadScanIds,
                    generation: generation
                )
                MerianLog.data.debug(
                    "syncPendingScans: tracking upload preparation ids=\(candidateUploadScanIds.sorted().joined(separator: ","), privacy: .private)"
                )
            }

            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let claimedScanIds = await dbActor.markScansAsUploading(scanIds: Array(candidateUploadScanIds))
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            await MainActor.run {
                for scanId in claimedScanIds {
                    self.uploadCompletionStates[scanId] = nil
                    self.latestUploadGenerations[scanId] = generation
                }
                self.userRequestedLargeUploadScanIds.subtract(claimedScanIds)
            }
            MerianLog.data.debug(
                "syncPendingScans: claimed scans=\(claimedScanIds.count, privacy: .public) ids=\(claimedScanIds.sorted().joined(separator: ","), privacy: .private)"
            )
            let unclaimedScanIds = candidateUploadScanIds.subtracting(claimedScanIds)
            if !unclaimedScanIds.isEmpty {
                await MainActor.run {
                    self.clearUploadPreparation(
                        scanIds: unclaimedScanIds,
                        generation: generation
                    )
                }
            }
            let claimedUploadPairs = zip(uploadItems, preparation.uploadFiles).filter { claimedScanIds.contains($0.0.scanId) }
            let claimedUploadItems = claimedUploadPairs.map { $0.0 }
            let claimedUploadFiles = claimedUploadPairs.map { $0.1 }

            guard !claimedUploadItems.isEmpty else {
                MerianLog.data.error("syncPendingScans: no scans could be claimed for upload; leaving queue for retry")
                await MainActor.run {
                    self.clearUploadPreparation(
                        scanIds: candidateUploadScanIds,
                        generation: generation
                    )
                    self.finishUploadSync(generation: generation)
                }
                return
            }

            do {
                let presignedUrls = try await MerianNetworkClient.shared.generateUploadURLs(
                    uploadFiles: claimedUploadFiles
                )
                guard await MainActor.run(body: {
                    self.isCurrentUploadSync(generation)
                }) else { return }
                MerianLog.data.debug(
                    "syncPendingScans: received presigned URLs=\(presignedUrls.count, privacy: .public)"
                )
                guard MediaStagingContract.presignedUploadManifestIsValid(
                    uploadItems: claimedUploadItems,
                    presignedURLs: presignedUrls
                ) else {
                    MerianLog.data.error(
                        "syncPendingScans: rejected an invalid staging response manifest"
                    )
                    throw MerianError.invalidResponse
                }
                let dispatchedScanIDs = await self.dispatchUploadTasks(
                    session: session,
                    uploadItems: claimedUploadItems,
                    presignedUrls: presignedUrls,
                    syncGeneration: generation
                )
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation) else { return }
                    self.clearUploadPreparation(
                        scanIds: claimedScanIds,
                        generation: generation
                    )
                    MerianLog.data.debug(
                        "syncPendingScans: cleared upload preparation ids=\(claimedScanIds.sorted().joined(separator: ","), privacy: .private) dispatched=\(dispatchedScanIDs.sorted().joined(separator: ","), privacy: .private)"
                    )
                }

                if dispatchedScanIDs.isEmpty {
                    let taskCount = await self.activeUploadTaskCount(
                        session: session,
                        generation: generation
                    )
                    MerianLog.data.debug(
                        "syncPendingScans: dispatched no upload tasks activeTaskCount=\(taskCount, privacy: .public)"
                    )
                    if taskCount == 0 {
                        _ = await MainActor.run {
                            self.finishUploadSync(generation: generation)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation) else { return }
                    self.clearUploadPreparation(
                        scanIds: claimedScanIds,
                        generation: generation
                    )
                }
                await self.handleSyncNetworkFailure(
                    error: error,
                    affectedScanIds: claimedScanIds,
                    session: session,
                    dbActor: dbActor,
                    syncGeneration: generation
                )
                return
            }

            // Failsafe: if no tasks were spawned, unlock manually.
            let activeTaskCount = await self.activeUploadTaskCount(
                session: session,
                generation: generation
            )
            MerianLog.data.debug(
                "syncPendingScans: active task count after dispatch=\(activeTaskCount, privacy: .public)"
            )
            if activeTaskCount == 0 {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
            }
        }
    }

    private func activeUploadTaskCount(
        session: URLSession,
        generation: UUID
    ) async -> Int {
        let tasks = await session.allTasks
        return tasks.filter { task in
            guard task.state != .canceling,
                  task.state != .completed,
                  let identity = MediaStagingContract.parseUploadTaskDescription(
                    task.taskDescription
                  ) else {
                return false
            }
            return identity.syncGeneration == generation
        }.count
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

    private func trackUploadPreparation(
        scanIds: Set<String>,
        generation: UUID
    ) {
        for scanId in scanIds {
            uploadPreparationGenerations[scanId] = generation
        }
    }

    private func clearUploadPreparation(
        scanIds: Set<String>,
        generation: UUID
    ) {
        for scanId in scanIds
        where uploadPreparationGenerations[scanId] == generation {
            uploadPreparationGenerations[scanId] = nil
        }
    }

    // MARK: - Upload Helpers

    nonisolated func currentMediaStagingUserId() async -> String {
        // The persisted Auth session is the source of truth even while
        // SupabaseManager.currentUser is still hydrating after a cold launch.
        // This also keeps the pre-V33 staged-key recovery path on the same owner
        // namespace that the authenticated upload endpoint used.
        let sessionUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let (hydratedUserId, deviceId) = await MainActor.run {
            (
                SupabaseManager.shared.currentUser?.id.uuidString,
                DeviceIdentityManager.shared.deviceId
            )
        }

        return MediaStagingContract.preferredOwnerId(
            sessionUserId: sessionUserId,
            hydratedUserId: hydratedUserId,
            deviceId: deviceId
        )
    }

    nonisolated private func prepareUploadItems(
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

    nonisolated private func selectUploadBatch(from scans: [PendingScanPayload]) -> [PendingScanPayload] {
        let maxPresignedURLsPerRequest = MediaStagingContract.maxUploadItemsPerRequest
        var selected: [PendingScanPayload] = []
        selected.reserveCapacity(MerianConfig.uploadBatchSize)
        var uploadItemCount = 0

        for scan in scans.prefix(MerianConfig.uploadBatchSize) {
            let scanUploadCount = scan.localUploadPaths.count
            guard scanUploadCount > 0 else { continue }
            if !selected.isEmpty, uploadItemCount + scanUploadCount > maxPresignedURLsPerRequest {
                break
            }
            selected.append(scan)
            uploadItemCount += scanUploadCount
            if uploadItemCount >= maxPresignedURLsPerRequest {
                break
            }
        }

        return selected
    }

    private func dispatchUploadTasks(
        session: URLSession,
        uploadItems: [ScanUploadItem],
        presignedUrls: [PreSignedURL],
        syncGeneration: UUID
    ) async -> Set<String> {
        return await withTaskGroup(of: String?.self) { group in
            for (index, presignedURL) in presignedUrls.enumerated() {
                guard !Task.isCancelled else { break }
                guard index < uploadItems.count else {
                    MerianLog.data.debug("dispatchUploadTasks: index \(index) out of bounds — skipping")
                    continue
                }
                guard let remoteUrl = URL(string: presignedURL.signedUrl) else {
                    MerianLog.data.debug("dispatchUploadTasks: invalid signed URL at index \(index) — skipping")
                    continue
                }

                let item = uploadItems[index]

                guard presignedURL.fileName == item.fileName,
                      MediaStagingContract.isCanonicalObjectKey(
                        presignedURL.objectKey,
                        fileName: item.fileName
                      ),
                      MediaStagingContract.objectKey(
                        fromPresignedURLPath: remoteUrl.path
                      ) == presignedURL.objectKey else {
                    MerianLog.data.error("dispatchUploadTasks: staging contract mismatch for \(item.scanId, privacy: .private)")
                    guard isCurrentUploadSync(syncGeneration),
                          latestUploadGenerations[item.scanId] == syncGeneration else {
                        continue
                    }
                    softDeleteQueuedScan(
                        scanId: item.scanId,
                        reason: "The upload destination could not be verified.",
                        errorCode: "staging_contract_mismatch"
                    )
                    continue
                }

                guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
                    MerianLog.data.debug("dispatchUploadTasks: source missing for \(item.fileURL.lastPathComponent, privacy: .private)")
                    guard isCurrentUploadSync(syncGeneration),
                          latestUploadGenerations[item.scanId] == syncGeneration else {
                        continue
                    }
                    softDeleteQueuedScan(
                        scanId: item.scanId,
                        reason: "The queued media file is no longer available.",
                        errorCode: "queued_media_missing"
                    )
                    continue
                }

                group.addTask { () -> String? in
                    guard !Task.isCancelled else { return nil }
                    guard await MainActor.run(body: {
                        self.isCurrentUploadSync(syncGeneration)
                    }) else { return nil }
                    var request = URLRequest(url: remoteUrl)
                    request.httpMethod = "PUT"
                    request.setValue(item.contentType, forHTTPHeaderField: "Content-Type")
                    let uploadTask = session.uploadTask(with: request, fromFile: item.fileURL)
                    uploadTask.taskDescription = MediaStagingContract.uploadTaskDescription(
                        scanId: item.scanId,
                        uploadIndex: item.uploadIndex,
                        syncGeneration: syncGeneration,
                        objectKey: presignedURL.objectKey
                    )
                    let didResume = await MainActor.run {
                        guard self.isCurrentUploadSync(syncGeneration) else {
                            uploadTask.cancel()
                            return false
                        }
                        uploadTask.resume()
                        return true
                    }
                    guard didResume else { return nil }
                    MerianLog.data.debug("🚀 BACKGROUND UPLOAD: Dispatched upload task for \(item.scanId, privacy: .private)")
                    return item.scanId
                }
            }

            var dispatchedIds = Set<String>()
            for await successfulScanId in group {
                if let id = successfulScanId { dispatchedIds.insert(id) }
            }
            return dispatchedIds
        }
    }

    private func handleSyncNetworkFailure(
        error: Error,
        affectedScanIds: Set<String>,
        session: URLSession,
        dbActor: BackgroundDatabaseActor,
        syncGeneration: UUID
    ) async {
        guard isCurrentUploadSync(syncGeneration) else { return }
        MerianLog.data.debug("syncPendingScans: staging URL request failed: \(error, privacy: .private)")

        // Reset orphaned uploads
        let observedThrough = Date()
        let liveTasks = await session.allTasks
        guard isCurrentUploadSync(syncGeneration) else { return }
        let activeUploadIds = Set(liveTasks.compactMap { task in
            MediaStagingContract.parseUploadTaskDescription(task.taskDescription)?.scanId
        })
        await dbActor.reconcileOrphanedUploadingScans(
            activeScanIds: activeUploadIds,
            observedThrough: observedThrough
        )
        guard isCurrentUploadSync(syncGeneration) else { return }

        var retryDelays: [TimeInterval] = []
        for scanId in affectedScanIds {
            let currentAttempt = queueAttemptCount(for: scanId)
            guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: currentAttempt) else {
                markQueuedScanNeedsAttention(
                    scanId: scanId,
                    code: "automatic_retry_limit_reached",
                    message: OfflineQueueRetryPolicy.automaticRetryLimitMessage()
                )
                continue
            }

            let delay = OfflineQueueRetryPolicy.jitteredDelay(forAttempt: currentAttempt + 1)
            let persistedAttempt = updateQueuedScanForRetry(
                scanId: scanId,
                code: "upload_url_generation_failed",
                message: error.localizedDescription,
                delay: delay,
                resetTo: .pending
            )
            if persistedAttempt == nil {
                // Keep a process-local fallback even when the durable retry
                // metadata could not be saved. The preceding orphan reconcile
                // leaves successfully persisted rows pending; foreground and
                // connectivity recovery remain additional wake opportunities.
                MerianLog.data.error(
                    "syncPendingScans: retry persistence failed scanId=\(scanId, privacy: .private)"
                )
            }
            retryDelays.append(delay)
        }

        guard let delay = retryDelays.min() else {
            finishUploadSync(generation: syncGeneration)
            retryBackoffTask?.cancel()
            retryBackoffTask = nil
            return
        }

        finishUploadSync(generation: syncGeneration)
        retryBackoffTask?.cancel()
        retryBackoffTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.syncPendingScans()
        }
    }

    // MARK: - Collections

    /// Marks collections as needing sync and attempts to push them immediately if online.
    /// The "Favorites" collection is excluded — it is managed locally only.
    func enqueueCollectionSync() {
        markCollectionSyncPending()
        syncCollectionsIfPending()
    }

    var hasPendingCollectionSyncJob: Bool {
        guard let context = modelContext else {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        }
        guard let job = fetchCollectionSyncJob(context: context) else { return false }
        return isActiveCollectionSyncStatus(job.statusRaw)
    }

    private var isCollectionSyncJobRunnable: Bool {
        guard let context = modelContext else {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        }
        guard let job = fetchCollectionSyncJob(context: context),
              isActiveCollectionSyncStatus(job.statusRaw) else { return false }
        if let nextRunAt = job.nextRunAt, nextRunAt > Date() {
            return false
        }
        return true
    }

    private func fetchCollectionSyncJob(context: ModelContext) -> OfflineJobRecord? {
        let jobId = Self.collectionSyncJobId
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func isActiveCollectionSyncStatus(_ statusRaw: String) -> Bool {
        statusRaw == OfflineJobStatus.pending.rawValue ||
            statusRaw == OfflineJobStatus.waiting.rawValue ||
            statusRaw == OfflineJobStatus.running.rawValue
    }

    /// Pushes local `ScanCollection` records to the `sync-collections` Edge function if changes are pending.
    /// No-ops when offline or unauthenticated.
    func syncCollectionsIfPending() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.drainCollectionSyncIfPossible()
        }
    }

    /// Shared collection-sync drain used by both fire-and-forget UI edits and the
    /// launch-time historical sync. This guarantees all collection pushes pass through
    /// the same single-flight latch, so a stale upsert can never race a newer tombstone.
    @discardableResult
    func drainCollectionSyncIfPossible() async -> Bool {
        while hasPendingCollectionSyncJob {
            guard isOnline, SupabaseManager.shared.isAuthenticated else { return false }
            guard isCollectionSyncJobRunnable else { return false }

            if let existingTask = collectionSyncTask {
                let didSucceed = await existingTask.value
                guard didSucceed else { return false }
                continue
            }

            guard let container = modelContext?.container else { return false }

            let capturedRevision = collectionSyncRevision
            isCollectionSyncing = true
            markCollectionSyncStarted()

            let task = BackgroundTaskWrapper.execute(name: "CollectionSync") { [weak self] _ in
                guard let self else { return false }
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                let success = await dbActor.pushCollectionsToEdge()

                await MainActor.run {
                    self.finishCollectionSyncAttempt(success: success, capturedRevision: capturedRevision)
                }

                return success
            }

            collectionSyncTask = task
            let didSucceed = await task.value
            guard didSucceed else { return false }
        }

        return true
    }

    func markCollectionSyncPending() {
        collectionSyncRevision &+= 1
        guard let context = modelContext else {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
            return
        }
        do {
            let job = try context.ensureOfflineJobRecord(
                id: Self.collectionSyncJobId,
                kind: .collectionSync,
                priority: 80
            )
            job.status = .pending
            job.attemptCount = 0
            job.updatedAt = Date()
            job.nextRunAt = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                kind: .queued,
                message: "Queued collection sync."
            ))
            try context.save()
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
        } catch {
            context.rollback()
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
            MerianLog.data.error("markCollectionSyncPending: save failed: \(error, privacy: .private)")
        }
    }

    func finishCollectionSyncAttempt(success: Bool, capturedRevision: UInt64) {
        isCollectionSyncing = false
        collectionSyncTask = nil

        guard let context = modelContext else {
            if success, collectionSyncRevision == capturedRevision {
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
            }
            return
        }

        let jobId = Self.collectionSyncJobId
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = (try? context.fetch(descriptor))?.first else { return }
        job.updatedAt = Date()
        if success, collectionSyncRevision == capturedRevision {
            job.status = .complete
            job.nextRunAt = nil
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
            context.insert(OfflineQueueEvent(jobId: job.id, kind: .completed, message: "Collection sync completed."))
        } else if !success {
            job.lastAttemptAt = Date()
            if OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: job.attemptCount) {
                job.attemptCount += 1
                job.status = .waiting
                job.nextRunAt = Date().addingTimeInterval(
                    OfflineQueueRetryPolicy.jitteredDelay(forAttempt: job.attemptCount)
                )
                job.lastErrorCode = "collection_sync_failed"
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    kind: .retryScheduled,
                    message: "Collection sync will retry.",
                    errorCode: "collection_sync_failed"
                ))
            } else {
                job.status = .needsAttention
                job.nextRunAt = nil
                job.lastErrorCode = "collection_sync_retry_limit_reached"
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    kind: .needsAttention,
                    message: "Collection sync paused after repeated failures.",
                    errorCode: "collection_sync_retry_limit_reached"
                ))
            }
        }
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("finishCollectionSyncAttempt: save failed: \(error, privacy: .private)")
        }
    }

    private func markCollectionSyncStarted() {
        guard let context = modelContext else { return }
        let jobId = Self.collectionSyncJobId
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = (try? context.fetch(descriptor))?.first else { return }
        job.status = .running
        job.updatedAt = Date()
        job.lastAttemptAt = Date()
        job.nextRunAt = nil
        context.insert(OfflineQueueEvent(jobId: job.id, kind: .claimed, message: "Collection sync started."))
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("markCollectionSyncStarted: save failed: \(error, privacy: .private)")
        }
    }
}
