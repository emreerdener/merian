import CoreLocation
import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private enum InferencePreparationFailure: Error {
    case timedOut
}

enum ScanStatusRecoveryAction: Equatable {
    case recovered
    case waitForServer(TimeInterval)
    case retryAfter(TimeInterval)
    case terminalFailure(String?)
    case unresolved
}

enum CompletedServerResultHydrationOutcome: Equatable, Sendable {
    case recovered
    case retryable
    case contractMismatch
}

enum BackgroundInferenceResponseDisposition: Equatable {
    case success
    case retry
    case consentRequired
    case needsAttention
    case terminal
}

private let requiredConsentAttentionMessage =
    "Complete the required age, Terms, and Google Gemini consent step. Naturebook will automatically resume the eligible saved scan; if it stays paused, you can retry it from Scans."

private let backgroundAccountWorkQuiescenceTimeout: Duration = .seconds(30)

// MARK: - Account-bound URLSession ownership

extension OfflineQueueManager {
    /// A transport that lost its Auth lease must remain suspended until its
    /// durable queue owner has been requeued. Retrying here keeps the original
    /// account-work lease alive, so an Auth transition cannot advance past a
    /// transient SwiftData failure and leave `.uploading` or `.inferencing`
    /// stranded after the task is cancelled.
    @discardableResult
    static func awaitDurableBackgroundWorkRetirement(
        maximumAttempts: Int = 3,
        retire: () async -> Bool,
        waitBeforeRetry: () async -> Bool
    ) async -> Bool {
        guard maximumAttempts > 0 else { return false }
        for attempt in 1...maximumAttempts {
            if await retire() {
                return true
            }
            guard attempt < maximumAttempts,
                  !Task.isCancelled,
                  await waitBeforeRetry() else {
                return false
            }
        }
        return false
    }

    static func waitForDurableBackgroundWorkRetirementRetry() async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(250))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    @discardableResult
    func retainBackgroundAccountWork(
        _ lease: AccountBoundWorkLease,
        for taskIdentifier: Int
    ) -> Bool {
        guard backgroundAccountWorkLeases[taskIdentifier] == nil,
              SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease)
        else {
            return false
        }
        backgroundAccountWorkLeases[taskIdentifier] = lease
        return true
    }

    func finishBackgroundAccountWork(for taskIdentifier: Int) {
        guard let lease = backgroundAccountWorkLeases.removeValue(
            forKey: taskIdentifier
        ) else {
            return
        }
        SupabaseManager.shared.finishAccountBoundWork(lease)
    }

    private func backgroundTaskOwnerLeaseIsCurrentOrAdopted(
        taskIdentifier: Int,
        ownerUserID: UUID
    ) -> Bool {
        if let lease = backgroundAccountWorkLeases[taskIdentifier] {
            return lease.session.userID == ownerUserID
                && SupabaseManager.shared
                    .isAccountBoundWorkLeaseCurrent(lease)
        }
        // Relaunched URLSession tasks do not carry their process-local lease.
        // Reacquire one synchronously on MainActor before the first actor
        // suspension so an Auth transition cannot begin after owner validation
        // and overtake terminal persistence.
        guard let lease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork(expectedUserID: ownerUserID) else {
            return false
        }
        guard retainBackgroundAccountWork(
            lease,
            for: taskIdentifier
        ) else {
            SupabaseManager.shared.finishAccountBoundWork(lease)
            return false
        }
        return true
    }

    private func validateOrAdoptBackgroundAccountWork(
        scanId: String,
        generation: UUID?,
        ownerUserID: UUID?,
        phase: BackgroundAccountWorkPhase,
        taskIdentifier: Int
    ) async -> BackgroundAccountWorkOwnership? {
        guard let ownerUserID, let generation,
              backgroundTaskOwnerLeaseIsCurrentOrAdopted(
                  taskIdentifier: taskIdentifier,
                  ownerUserID: ownerUserID
              ),
              let container = modelContext?.container else {
            return nil
        }
        let ownership = BackgroundAccountWorkOwnership(
            ownerUserID: ownerUserID,
            generation: generation,
            phase: phase
        )
        let actor = resolvedQueueDbActor(container: container)
        if await actor.backgroundAccountWorkIsCurrent(
            scanId: scanId,
            ownership: ownership
        ) {
            return ownership
        }
        // A modern task may be reattached after process termination before its
        // callback. The task's explicit account/generation pair is sufficient
        // to re-adopt only while the exact stable Auth session and expected
        // queue state still exist.
        guard await actor.activateBackgroundAccountWork(
            scanId: scanId,
            ownership: ownership
        ) else {
            return nil
        }
        return ownership
    }

    /// Closes every URLSession account-work lane before Auth can mutate.
    /// Durable queue retreat commits before task cancellation; then this waits
    /// for both transport disappearance and terminal callback lease release.
    func quiesceBackgroundAccountWorkForAuthTransition(
        sourceUserID: UUID?
    ) async -> Bool {
        syncTask?.cancel()
        retryBackoffTask?.cancel()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: backgroundAccountWorkQuiescenceTimeout
        )

        while true {
            guard !Task.isCancelled else { return false }
            guard let container = modelContext?.container else {
                return false
            }
            let actor = resolvedQueueDbActor(container: container)
            guard let durableCandidates = await actor
                .backgroundAccountWorkCandidates(ownerUserID: sourceUserID)
            else {
                return false
            }
            let tasks = await backgroundSession.allTasks
            let accountTasks = tasks.filter {
                InferenceURLSessionTaskContract.parse($0.taskDescription) != nil
                    || MediaStagingContract.parseUploadTaskDescription(
                        $0.taskDescription
                    ) != nil
            }
            var cancellableTaskIdentifiers = Set<Int>()
            var retirementFailed = false
            var retirementResults = [String: Bool]()

            func retirementKey(
                scanId: String,
                ownerUserID: UUID?,
                generation: UUID,
                phase: BackgroundAccountWorkPhase
            ) -> String {
                "\(phase.rawValue)|\(ownerUserID?.uuidString ?? "unknown")|\(scanId)|\(generation.uuidString)"
            }

            for candidate in durableCandidates {
                let ownership = candidate.ownership
                let key = retirementKey(
                    scanId: candidate.scanId,
                    ownerUserID: ownership.ownerUserID,
                    generation: ownership.generation,
                    phase: ownership.phase
                )
                guard retirementResults[key] == nil else { continue }
                let didPersistRetirement = await actor
                    .retireBackgroundAccountWork(
                        scanId: candidate.scanId,
                        expectedOwnerUserID: ownership.ownerUserID,
                        expectedGeneration: ownership.generation,
                        phase: ownership.phase
                    )
                retirementResults[key] = didPersistRetirement
                retirementFailed = retirementFailed || !didPersistRetirement
            }

            for task in accountTasks {
                if let identity = InferenceURLSessionTaskContract.parse(
                    task.taskDescription
                ) {
                    let didPersistRetirement: Bool
                    if let generation = identity.generation {
                        let key = retirementKey(
                            scanId: identity.scanId,
                            ownerUserID:
                                identity.ownerUserID ?? sourceUserID,
                            generation: generation,
                            phase: .inference
                        )
                        if let existingResult = retirementResults[key] {
                            didPersistRetirement = existingResult
                        } else {
                            didPersistRetirement = await actor
                                .retireBackgroundAccountWork(
                                    scanId: identity.scanId,
                                    expectedOwnerUserID:
                                        identity.ownerUserID ?? sourceUserID,
                                    expectedGeneration: generation,
                                    phase: .inference
                                )
                            retirementResults[key] = didPersistRetirement
                        }
                    } else {
                        didPersistRetirement = await actor
                            .retireBackgroundAccountWork(
                                scanId: identity.scanId,
                                expectedOwnerUserID:
                                    identity.ownerUserID ?? sourceUserID,
                                expectedGeneration: nil,
                                phase: .inference
                            )
                    }
                    if didPersistRetirement {
                        cancellableTaskIdentifiers.insert(task.taskIdentifier)
                        if let generation = identity.generation {
                            retiredInferenceGenerations.insert(generation)
                            if activeInferenceGenerations[identity.scanId]
                                == generation {
                                activeInferenceGenerations[identity.scanId] = nil
                            }
                        }
                    } else {
                        retirementFailed = true
                    }
                } else if let identity = MediaStagingContract
                    .parseUploadTaskDescription(task.taskDescription) {
                    let didPersistRetirement: Bool
                    if let generation = identity.syncGeneration {
                        let key = retirementKey(
                            scanId: identity.scanId,
                            ownerUserID:
                                identity.ownerUserID ?? sourceUserID,
                            generation: generation,
                            phase: .upload
                        )
                        if let existingResult = retirementResults[key] {
                            didPersistRetirement = existingResult
                        } else {
                            didPersistRetirement = await actor
                                .retireBackgroundAccountWork(
                                    scanId: identity.scanId,
                                    expectedOwnerUserID:
                                        identity.ownerUserID ?? sourceUserID,
                                    expectedGeneration: generation,
                                    phase: .upload
                                )
                            retirementResults[key] = didPersistRetirement
                        }
                    } else {
                        didPersistRetirement = await actor
                            .retireBackgroundAccountWork(
                                scanId: identity.scanId,
                                expectedOwnerUserID:
                                    identity.ownerUserID ?? sourceUserID,
                                expectedGeneration: nil,
                                phase: .upload
                            )
                    }
                    if didPersistRetirement {
                        cancellableTaskIdentifiers.insert(task.taskIdentifier)
                        invalidateUploadGeneration(
                            scanId: identity.scanId,
                            generation: identity.syncGeneration
                        )
                    } else {
                        retirementFailed = true
                    }
                }
            }

            guard !retirementFailed else { return false }

            for task in accountTasks where
                cancellableTaskIdentifiers.contains(task.taskIdentifier) {
                task.cancel()
            }

            if durableCandidates.isEmpty,
               accountTasks.isEmpty,
               backgroundAccountWorkLeases.isEmpty {
                return true
            }
            guard clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
    }
}

// MARK: - URLSession Delegate

extension OfflineQueueManager: URLSessionTaskDelegate, URLSessionDownloadDelegate {

    /// Fires when an inference background download task delivers its response body to a temp file.
    ///
    /// The temp file is only valid for the duration of this callback — copy it immediately.
    /// All result processing happens in `processInferenceDownloadResult` via a BackgroundTaskWrapper
    /// so iOS grants extended execution time to complete the SwiftData write and push notification.
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let taskIdentity = InferenceURLSessionTaskContract.parse(
            downloadTask.taskDescription
        ) else { return }

        let scanId = taskIdentity.scanId
        let generation = taskIdentity.generation
        let ownerUserID = taskIdentity.ownerUserID
        let httpResponse = downloadTask.response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode
        let functionRouteEvidence = httpResponse.map {
            EdgeFunctionRouteResponseEvidence(response: $0)
        }
        let taskIdentifier = downloadTask.taskIdentifier
        MerianLog.data.debug(
            "urlSession didFinishDownloadingTo: inference scanId=\(scanId, privacy: .private) status=\(statusCode ?? -1, privacy: .public)"
        )

        // Copy the temp file before the system deletes it at callback return.
        let tempDestination = URL.temporaryDirectory.appendingPathComponent(
            "\(scanId)_\(taskIdentifier)_inference.json"
        )
        try? FileManager.default.removeItem(at: tempDestination)
        do {
            try FileManager.default.copyItem(at: location, to: tempDestination)
        } catch {
            MerianLog.data.error("Background inference download: failed to preserve temp file for \(scanId, privacy: .private): \(error, privacy: .private)")
            let terminalToken = OfflineQueueManager
                .backgroundTerminalWorkTracker.begin()
            BackgroundTaskWrapper.execute(name: "OfflineInferenceError") { _ in
                defer {
                    OfflineQueueManager.backgroundTerminalWorkTracker
                        .finish(terminalToken)
                }
                await OfflineQueueManager.shared
                    .processInferenceTerminalFailure(
                    scanId: scanId,
                    generation: generation,
                    ownerUserID: ownerUserID,
                    taskIdentifier: taskIdentifier,
                    error: error
                )
            }
            return
        }

        let terminalToken = OfflineQueueManager
            .backgroundTerminalWorkTracker.begin()
        BackgroundTaskWrapper.execute(name: "OfflineInferenceResult") { _ in
            defer {
                OfflineQueueManager.backgroundTerminalWorkTracker
                    .finish(terminalToken)
            }
            await OfflineQueueManager.shared.processInferenceTerminalResult(
                scanId: scanId,
                generation: generation,
                ownerUserID: ownerUserID,
                taskIdentifier: taskIdentifier,
                resultFileURL: tempDestination,
                statusCode: statusCode,
                functionRouteEvidence: functionRouteEvidence
            )
        }
    }

    /// Fires when the background URLSession completes transmission of a task (upload or download).
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Capture non-Sendable properties before crossing isolation boundaries.
        let taskDescription = task.taskDescription
        let originalRequestUrlPath = task.originalRequest?.url?.path
        let responseStatusCode = (task.response as? HTTPURLResponse)?.statusCode
        let taskIdentifier = task.taskIdentifier
        let terminalToken = OfflineQueueManager
            .backgroundTerminalWorkTracker.begin()

        BackgroundTaskWrapper.execute(
            name: "OfflineInference",
            expirationHandler: { MerianLog.data.debug("OfflineInference background task expired") }
        ) { _ in
            defer {
                OfflineQueueManager.backgroundTerminalWorkTracker
                    .finish(terminalToken)
            }
            // Route inference download task failures.
            // On success, didFinishDownloadingTo already handled the result — skip here.
            if let inferenceIdentity = InferenceURLSessionTaskContract.parse(taskDescription) {
                let scanId = inferenceIdentity.scanId
                MerianLog.data.debug(
                    "urlSession didCompleteWithError: inference scanId=\(scanId, privacy: .private) status=\(responseStatusCode ?? -1, privacy: .public) error=\((error?.localizedDescription ?? "nil"), privacy: .private)"
                )
                if let error {
                    await OfflineQueueManager.shared
                        .processInferenceTerminalFailure(
                        scanId: scanId,
                        generation: inferenceIdentity.generation,
                        ownerUserID: inferenceIdentity.ownerUserID,
                        taskIdentifier: taskIdentifier,
                        error: error
                    )
                }
                // Inference tasks are not counted in the upload isSyncing state machine.
                return
            }

            await OfflineQueueManager.shared.processUploadTerminalCallback(
                taskDescription: taskDescription,
                originalRequestUrlPath: originalRequestUrlPath,
                responseStatusCode: responseStatusCode,
                uploadError: error,
                taskIdentifier: taskIdentifier,
                session: session
            )
        }
    }

    /// Called by iOS when all background session events have been delivered.
    /// Invokes the stored completion handler so the system knows it's safe to suspend the app.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            await OfflineQueueManager
                .invokeBackgroundSessionCompletionAfterTerminalWork(
                    tracker: OfflineQueueManager
                        .backgroundTerminalWorkTracker,
                    takeHandler: {
                        let handler = OfflineQueueManager.shared
                            .backgroundCompletionHandler
                        OfflineQueueManager.shared
                            .backgroundCompletionHandler = nil
                        return handler
                    }
                )
        }
    }
}

// MARK: - Upload Completion & Inference Pipeline

extension OfflineQueueManager {

    func processUploadTerminalCallback(
        taskDescription: String?,
        originalRequestUrlPath: String?,
        responseStatusCode: Int?,
        uploadError: Error?,
        taskIdentifier: Int,
        session: URLSession
    ) async {
        defer { finishBackgroundAccountWork(for: taskIdentifier) }
        guard let identity = MediaStagingContract
            .parseUploadTaskDescription(taskDescription) else {
            return
        }
        let ownership = await validateOrAdoptBackgroundAccountWork(
            scanId: identity.scanId,
            generation: identity.syncGeneration,
            ownerUserID: identity.ownerUserID,
            phase: .upload,
            taskIdentifier: taskIdentifier
        )
        guard ownership != nil else {
            let didRetire = await Self.awaitDurableBackgroundWorkRetirement(
                retire: {
                    await self.retireRejectedBackgroundAccountWork(
                        scanId: identity.scanId,
                        generation: identity.syncGeneration,
                        ownerUserID: identity.ownerUserID,
                        phase: .upload
                    )
                },
                waitBeforeRetry: {
                    await Self
                        .waitForDurableBackgroundWorkRetirementRetry()
                }
            )
            if didRetire {
                invalidateUploadGeneration(
                    scanId: identity.scanId,
                    generation: identity.syncGeneration
                )
            }
            return
        }

        await processUploadCompletion(
            taskDescription: taskDescription,
            originalRequestUrlPath: originalRequestUrlPath,
            responseStatusCode: responseStatusCode,
            uploadError: uploadError,
            taskIdentifier: taskIdentifier,
            session: session
        )

        let remaining = await session.allTasks
        let activeUploadTasks = remaining.filter {
            guard $0.taskIdentifier != taskIdentifier,
                  let other = MediaStagingContract
                    .parseUploadTaskDescription($0.taskDescription) else {
                return false
            }
            return other.syncGeneration == identity.syncGeneration
        }
        if activeUploadTasks.isEmpty {
            let didFinishCurrentSync = finishUploadSync(
                generation: identity.syncGeneration
            )
            replayInferenceForUploadedScans()
            if didFinishCurrentSync && unsyncedItemsCount > 0 {
                syncPendingScans()
            }
        }
    }

    func processInferenceTerminalResult(
        scanId: String,
        generation: UUID?,
        ownerUserID: UUID?,
        taskIdentifier: Int,
        resultFileURL: URL,
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence?
    ) async {
        defer { finishBackgroundAccountWork(for: taskIdentifier) }
        guard await validateOrAdoptBackgroundAccountWork(
            scanId: scanId,
            generation: generation,
            ownerUserID: ownerUserID,
            phase: .inference,
            taskIdentifier: taskIdentifier
        ) != nil else {
            try? FileManager.default.removeItem(at: resultFileURL)
            let didRetire = await Self.awaitDurableBackgroundWorkRetirement(
                retire: {
                    await self.retireRejectedBackgroundAccountWork(
                        scanId: scanId,
                        generation: generation,
                        ownerUserID: ownerUserID,
                        phase: .inference
                    )
                },
                waitBeforeRetry: {
                    await Self
                        .waitForDurableBackgroundWorkRetirementRetry()
                }
            )
            if didRetire, let generation {
                retiredInferenceGenerations.insert(generation)
            }
            return
        }
        await processInferenceDownloadResult(
            scanId: scanId,
            generation: generation,
            resultFileURL: resultFileURL,
            statusCode: statusCode,
            functionRouteEvidence: functionRouteEvidence
        )
    }

    func processInferenceTerminalFailure(
        scanId: String,
        generation: UUID?,
        ownerUserID: UUID?,
        taskIdentifier: Int,
        error: Error
    ) async {
        defer { finishBackgroundAccountWork(for: taskIdentifier) }
        guard await validateOrAdoptBackgroundAccountWork(
            scanId: scanId,
            generation: generation,
            ownerUserID: ownerUserID,
            phase: .inference,
            taskIdentifier: taskIdentifier
        ) != nil else {
            let didRetire = await Self.awaitDurableBackgroundWorkRetirement(
                retire: {
                    await self.retireRejectedBackgroundAccountWork(
                        scanId: scanId,
                        generation: generation,
                        ownerUserID: ownerUserID,
                        phase: .inference
                    )
                },
                waitBeforeRetry: {
                    await Self
                        .waitForDurableBackgroundWorkRetirementRetry()
                }
            )
            if didRetire, let generation {
                retiredInferenceGenerations.insert(generation)
            }
            return
        }
        await handleInferenceTaskNetworkFailure(
            scanId: scanId,
            generation: generation,
            error: error
        )
    }

    private func retireRejectedBackgroundAccountWork(
        scanId: String,
        generation: UUID?,
        ownerUserID: UUID?,
        phase: BackgroundAccountWorkPhase
    ) async -> Bool {
        guard let container = modelContext?.container else { return false }
        let actor = resolvedQueueDbActor(container: container)
        let didRetire = await actor.retireBackgroundAccountWork(
            scanId: scanId,
            expectedOwnerUserID: ownerUserID,
            expectedGeneration: generation,
            phase: phase
        )
        if didRetire {
            updateUnsyncedItemCount()
        }
        return didRetire
    }

    /// Processes the result of a completed background upload, then kicks off inference
    /// for the scan once all of its image files have landed in R2 staging.
    func processUploadCompletion(
        taskDescription: String?,
        originalRequestUrlPath: String?,
        responseStatusCode: Int?,
        uploadError: Error?,
        taskIdentifier: Int,
        session: URLSession
    ) async {
        guard let uploadIdentity = MediaStagingContract.parseUploadTaskDescription(taskDescription) else { return }
        let scanId = uploadIdentity.scanId
        guard isUploadGenerationCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration
        ) else {
            MerianLog.data.debug(
                "processUploadCompletion: ignored stale upload generation scanId=\(scanId, privacy: .public)"
            )
            return
        }

        let completionToken = beginUploadCompletion(scanId: scanId)
        defer {
            _ = finishUploadCompletion(
                scanId: scanId,
                token: completionToken
            )
            MerianLog.data.debug(
                "processUploadCompletion: cleared upload completion lock scanId=\(scanId, privacy: .public)"
            )
        }
        let uploadIndex = uploadIdentity.uploadIndex ?? -1
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) uploadIndex=\(uploadIndex, privacy: .public) status=\(responseStatusCode ?? -1, privacy: .public) error=\((uploadError?.localizedDescription ?? "nil"), privacy: .public)"
        )

        // Record this callback's outcome before the first suspension. URLSession
        // can remove a completed task before another callback's async handler
        // starts; yielding first would let a successful sibling inspect a
        // partial outcome set and mistake task disappearance for success.
        let didFail = handleUploadFallback(
            scanId: scanId,
            uploadError: uploadError,
            responseStatusCode: responseStatusCode,
            uploadGeneration: uploadIdentity.syncGeneration,
            completionToken: completionToken
        )
        if didFail {
            // One failed member invalidates the entire logical media manifest.
            // Otherwise a sibling that happens to complete last can observe no
            // active tasks and incorrectly advance the scan to `.staged`.
            invalidateUploadGeneration(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
            let remainingTasks = await session.allTasks
            for task in remainingTasks where task.taskIdentifier != taskIdentifier {
                guard let identity = MediaStagingContract.parseUploadTaskDescription(
                    task.taskDescription
                ), identity.scanId == scanId,
                   identity.syncGeneration == uploadIdentity.syncGeneration else {
                    continue
                }
                task.cancel()
            }
            return
        }

        // The exact server-issued object key travels with current background
        // tasks. Legacy tasks recover it from the signed URL path.
        let confirmedObjectKey = uploadIdentity.objectKey ??
            MediaStagingContract.objectKey(
                fromPresignedURLPath: originalRequestUrlPath
            )
        guard let confirmedObjectKey,
              let stagingUserId = MediaStagingContract.ownerId(
                fromObjectKey: confirmedObjectKey
              ) else {
            MerianLog.data.error(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) invalid staging destination"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: "The completed upload destination could not be verified.",
                errorCode: "staging_object_key_invalid"
            )
            return
        }
        recordSuccessfulUploadMember(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            objectKey: confirmedObjectKey
        )

        // Compute task state only after this callback's exact outcome has been
        // recorded. Every started sibling therefore publishes success or fences
        // failure before it can yield to this enumeration.
        let remainingTasks = await session.allTasks
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            MerianLog.data.debug(
                "processUploadCompletion: superseded while enumerating tasks scanId=\(scanId, privacy: .public)"
            )
            return
        }
        let hasReplacementTaskForScan = remainingTasks.contains {
            guard $0.taskIdentifier != taskIdentifier,
                  $0.state != .canceling,
                  $0.state != .completed,
                  let identity = MediaStagingContract.parseUploadTaskDescription(
                    $0.taskDescription
                  ) else {
                return false
            }
            return identity.scanId == scanId
                && identity.syncGeneration != uploadIdentity.syncGeneration
        }
        let hasReplacementPreparation = uploadPreparationGenerations[scanId]
            .map { $0 != uploadIdentity.syncGeneration } ?? false
        guard !hasReplacementTaskForScan, !hasReplacementPreparation else {
            MerianLog.data.debug(
                "processUploadCompletion: replacement upload owns scanId=\(scanId, privacy: .public)"
            )
            return
        }
        let hasActiveTasksForScan = remainingTasks.contains {
            guard $0.taskIdentifier != taskIdentifier,
                  let identity = MediaStagingContract.parseUploadTaskDescription(
                    $0.taskDescription
                  ) else {
                return false
            }
            return identity.scanId == scanId
                && identity.syncGeneration == uploadIdentity.syncGeneration
        }
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) hasActiveTasksForScan=\(hasActiveTasksForScan, privacy: .public) remainingTasks=\(remainingTasks.count, privacy: .public)"
        )

        // Ensure no other upload tasks for this specific scan ID are still in flight.
        // If they are, allow them to finish (the last one handles the inference triggering).
        // Guard here — before the main-actor metadata fetch and auth session lookup — so that
        // multi-image scans don't pay those costs on every intermediate completion (only the last).
        guard !hasActiveTasksForScan else {
            MerianLog.data.debug(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) waiting for remaining upload tasks"
            )
            return
        }

        // Fetch scan metadata on the main actor before handing off to background inference.
        let extracted = await fetchScanMetadata(for: scanId)
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            return
        }
        guard let extracted else {
            MerianLog.data.error(
                "processUploadCompletion: missing queued scan metadata scanId=\(scanId, privacy: .public)"
            )
            return
        }

        // Compute confirmed object keys through the shared media staging contract so
        // completion, replay, and request construction cannot drift on filename rules.
        let stagedKeys = MediaStagingContract.splitObjectKeys(
            [],
            scanId: scanId,
            userId: stagingUserId,
            localImagePaths: extracted.localImagePaths,
            localAudioPaths: extracted.audioFilePaths ?? [],
            localVideoPaths: extracted.videoFilePaths ?? []
        )
        let r2Keys = stagedKeys.all
        guard r2Keys.contains(confirmedObjectKey) else {
            MerianLog.data.error(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) completed object no longer belongs to queued media"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: "The completed upload no longer matches the queued capture.",
                errorCode: "staging_capture_identity_mismatch"
            )
            return
        }
        guard hasConfirmedSuccessfulUploadManifest(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            expectedObjectKeys: r2Keys
        ) else {
            // A completed sibling can disappear from URLSession.allTasks before
            // its asynchronous callback records either success or failure.
            // Wait for that callback; failure invalidates this generation and
            // success completes the exact-key set above.
            MerianLog.data.debug(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) waiting for sibling callback outcomes"
            )
            return
        }
        // Retry accounting belongs to the logical scan manifest, not an
        // individual file. The exact-key check above does not mutate durable
        // state; markScanAsStaged normally resets upload retry metadata in the
        // same save that commits the inference-ready transition. An exact
        // scheduled server-failure reclaim deliberately survives that save.
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            return
        }
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) staging complete keys=\(r2Keys.count, privacy: .public)"
        )

        // Use the same shared actor as replayInferenceForUploadedScans so that
        // markScanAsStaged and tryClaimForInference are serialized on a single executor.
        // This closes the race where processUploadCompletion and replayInferenceForUploadedScans
        // could both see the scan in .staged and both dispatch concurrent inference tasks.
        let queueActor = resolvedQueueDbActor(container: extracted.container)
        let stagingOutcome = await queueActor.markScanAsStaged(
            scanId: scanId,
            r2Keys: r2Keys
        )
        switch stagingOutcome {
        case .staged, .alreadyAdvanced:
            clearUploadCompletionState(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
        case .retryRequired:
            // Keep the exact successful-member set until the completion token
            // is released. The delegate envelope immediately replays from the
            // authoritative durable row: timestamp-fenced orphan recovery
            // resets a still-uploading row to pending and restarts signing,
            // while an already-staged row replays only its persisted keys.
            MerianLog.data.error(
                "processUploadCompletion: durable staging transition needs retry scanId=\(scanId, privacy: .private)"
            )
            return
        case .discarded:
            clearUploadCompletionState(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
            MerianLog.data.debug(
                "processUploadCompletion: discarded non-runnable staging completion scanId=\(scanId, privacy: .private)"
            )
            return
        }
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            return
        }

        // A background PUT started by a pre-WAV build can survive the app
        // upgrade. Its callback reaches this point as `.uploading`, so the
        // pending/staged startup repair could not have claimed it earlier.
        // Stage the exact completed manifest first, then synchronously retreat
        // the row to `.pending`, clear those compressed-audio keys, and rewrite
        // its durable media timeline before any inference claim is allowed.
        // Even if the repair claim loses a state race or its actor fetch fails,
        // never dispatch the known-incompatible M4A manifest; normal replay
        // will reconcile the authoritative durable state.
        if !extracted.capturedMediaSnapshot
            .legacyQueuedAudioReferences.isEmpty {
            let repairResult = await repairLegacyQueuedAudio(
                scanIds: [scanId],
                dbActor: queueActor
            )
            MerianLog.data.debug(
                "processUploadCompletion: intercepted legacy queued audio before inference scanId=\(scanId, privacy: .public) claimed=\(repairResult.claimedScanIds.contains(scanId), privacy: .public) repaired=\(repairResult.repairedScanIds.contains(scanId), privacy: .public)"
            )
            if repairResult.didMutate {
                syncPendingScans()
            } else {
                replayInferenceForUploadedScans()
            }
            return
        }

        // The foreground request still owns identification for this
        // queue-backed live submission. Keep the durable row staged, but do not
        // dispatch a second Gemini call. Foreground failure/backgrounding
        // releases this claim and replay picks the staged row up immediately.
        if foregroundInferenceScanIds.contains(scanId) {
            MerianLog.data.debug(
                "processUploadCompletion: staged recovery media while foreground inference owns scanId=\(scanId, privacy: .public)"
            )
            return
        }

        // Atomically claim the scan for inference. If replayInferenceForUploadedScans already
        // claimed it between markScanAsStaged and here (same actor, so serialized), skip —
        // the replay path already dispatched the background download task.
        guard let preparationGeneration = await MainActor.run(body: {
            self.beginInferencePreparation(scanId: scanId)
        }) else {
            MerianLog.data.debug(
                "processUploadCompletion: preparation already active scanId=\(scanId, privacy: .public)"
            )
            return
        }
        let didClaimInference = await queueActor.tryClaimForInference(
            scanId: scanId,
            generation: preparationGeneration
        )
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            clearInferencePreparation(
                scanId: scanId,
                generation: preparationGeneration
            )
            return
        }
        if !didClaimInference {
            MerianLog.data.debug(
                "processUploadCompletion: inference claim skipped scanId=\(scanId, privacy: .public)"
            )
            await MainActor.run {
                self.clearInferencePreparation(
                    scanId: scanId,
                    generation: preparationGeneration
                )
            }
            return
        }
        MerianLog.data.debug(
            "processUploadCompletion: inference claimed scanId=\(scanId, privacy: .public)"
        )

        // Rebuild extracted with the confirmed R2 keys before dispatching.
        let extractedWithKeys = ExtractedScanData(
            telemetry: extracted.telemetry,
            r2Keys: r2Keys,
            container: extracted.container,
            originalTimestamp: extracted.originalTimestamp,
            capturedMediaItems: extracted.capturedMediaItems,
            inferenceImagePaths: extracted.inferenceImagePaths,
            visualMediaItemsJSON: extracted.visualMediaItemsJSON,
            preferredGoal: extracted.preferredGoal
        )
        await dispatchInferenceDownloadTask(
            scanId: scanId,
            extracted: extractedWithKeys,
            preparationGeneration: preparationGeneration
        )
    }

    // MARK: - Post-Upload Helpers

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

    private func isUploadCompletionCurrent(
        scanId: String,
        generation: UUID?,
        token: UUID
    ) -> Bool {
        uploadCompletionTokens[scanId]?.contains(token) == true
            && isUploadGenerationCurrent(
                scanId: scanId,
                generation: generation
            )
    }

    /// Handles transport-level and HTTP-level upload errors.
    /// Returns `true` if an error was found and handled (caller should abort), `false` on success.
    private func handleUploadFallback(
        scanId: String,
        uploadError: Error?,
        responseStatusCode: Int?,
        uploadGeneration: UUID?,
        completionToken: UUID
    ) -> Bool {
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadGeneration,
            token: completionToken
        ) else {
            return true
        }
        let currentAttempt = queueAttemptCount(for: scanId)
        let disposition = OfflineQueueRetryPolicy.classifyUpload(
            error: uploadError,
            statusCode: responseStatusCode,
            currentAttempt: currentAttempt
        )

        switch disposition {
        case .success:
            recordQueueEvent(
                scanId: scanId,
                jobId: Self.scanIngestionJobId(scanId: scanId),
                kind: .uploadCompleted,
                message: "Queued scan media upload completed.",
                httpStatus: responseStatusCode
            )
            return false
        case .retry(let delay, let code, let message):
            let persistedAttempt = updateQueuedScanForRetry(
                scanId: scanId,
                code: code,
                message: message,
                httpStatus: responseStatusCode,
                delay: delay,
                resetTo: .pending
            )
            if let persistedAttempt {
                MerianLog.data.debug(
                    "handleUploadFallback: scheduled upload retry scanId=\(scanId, privacy: .private) attempt=\(persistedAttempt, privacy: .public) delay=\(String(format: "%.1f", delay), privacy: .public)s code=\(code, privacy: .public)"
                )
            } else {
                MerianLog.data.error(
                    "handleUploadFallback: retry persistence failed scanId=\(scanId, privacy: .private) delay=\(String(format: "%.1f", delay), privacy: .public)s code=\(code, privacy: .public)"
                )
            }
            return true
        case .needsAttention(let code, let message):
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: message,
                errorCode: code,
                httpStatus: responseStatusCode,
                needsAttention: true
            )
            return true
        case .terminal(let code, let message):
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: message,
                errorCode: code,
                httpStatus: responseStatusCode,
                needsAttention: false
            )
            return true
        case .waitForServer:
            return true
        }
    }

    /// Fetches the queued scan's snapshot and maps it to ExtractedScanData on the main actor.
    private func fetchScanMetadata(for scanId: String) async -> ExtractedScanData? {
        return await MainActor.run { () -> ExtractedScanData? in
            guard let context = OfflineQueueManager.shared.modelContext else { return nil }
            let container = context.container
            var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            let scan: OfflineQueuedScan?
            do {
                scan = try context.fetch(descriptor).first
            } catch {
                MerianLog.data.debug("urlSession: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                return nil
            }
            guard let scan else { return nil }
            return OfflineQueueManager.shared.buildExtractedScanData(from: scan, container: container)
        }
    }

    private func buildPreferredGoalHint(scanId: String) -> FieldTripPreferredGoal? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(
            predicate: #Predicate { $0.scanId == scanId }
        )
        descriptor.fetchLimit = 1
        guard let hint = try? context.fetch(descriptor).first else { return nil }
        return FieldTripPreferredGoal(
            userFieldTripId: hint.userFieldTripId,
            itemId: hint.itemId
        )
    }

    // MARK: - Scan Data Extraction

    /// Maps a queued scan record to a Sendable `ExtractedScanData` snapshot.
    /// Must be called while `scan` is accessible on the main actor.
    func buildExtractedScanData(from scan: OfflineQueuedScan, container: ModelContainer) -> ExtractedScanData {
        let preferredGoal: FieldTripPreferredGoal? = {
            let hintContext = ModelContext(container)
            let scanId = scan.id
            var descriptor = FetchDescriptor<ActiveOfflineQueuedScanGoalHint>(
                predicate: #Predicate { $0.scanId == scanId }
            )
            descriptor.fetchLimit = 1
            guard let hint = try? hintContext.fetch(descriptor).first else { return nil }
            return FieldTripPreferredGoal(
                userFieldTripId: hint.userFieldTripId,
                itemId: hint.itemId
            )
        }()
        let visualMediaItems: [IdentifyVisualMediaItem]? = scan.visualMediaItemsJSON.flatMap { json in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([IdentifyVisualMediaItem].self, from: data)
        }
        let firstImage = visualMediaItems?.first { $0.kind == .image }
        let shouldOmitQueueTimestamp = firstImage?.captureSource == .gallery
            && firstImage?.hasEmbeddedCaptureDate != true
        var telemetry = CaptureTelemetry(
            subjectDistanceInMeters: scan.subjectDistanceInMeters,
            gpsLatitude: scan.gpsLatitude,
            gpsLongitude: scan.gpsLongitude,
            gpsElevation: scan.gpsElevation,
            locationName: scan.locationName,
            weatherCondition: scan.weatherCondition,
            weatherTemperatureF: scan.weatherTemperatureF,
            timeOfDay: nil,
            timestamp: shouldOmitQueueTimestamp
                ? nil
                : DateUtilities.iso8601Formatter.string(from: scan.timestamp)
        )
        telemetry.zoomFactor = scan.zoomFactor.map { CGFloat($0) }

        return ExtractedScanData(
            telemetry: telemetry,
            r2Keys: scan.stagedR2Keys ?? [],
            container: container,
            originalTimestamp: scan.timestamp,
            capturedMediaItems: scan.serializedCapturedMediaItems,
            inferenceImagePaths: scan.inferenceImagePaths,
            visualMediaItemsJSON: scan.visualMediaItemsJSON,
            preferredGoal: preferredGoal
        )
    }

    // MARK: - Background Inference Dispatch

    private func claimInferenceGeneration(
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

    private func isInferenceGenerationCurrent(
        scanId: String,
        expectedGeneration: UUID?
    ) -> Bool {
        activeInferenceGenerations[scanId] == expectedGeneration
    }

    private func finishInferenceGeneration(
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

    /// Fetches WeatherKit backfill, builds an authenticated request, and dispatches it as a
    /// background URLSession download task so inference results arrive while the app is suspended.
    ///
    /// Weather backfill is persisted to SwiftData before dispatch so the delegate can read the
    /// hydrated telemetry from the store when the OS delivers the result — even after a relaunch.
    ///
    /// Task description carries both scan ID and a UUID generation so stale delegate,
    /// watchdog, and retry paths cannot act on a replacement attempt.
    func dispatchInferenceDownloadTask(
        scanId: String,
        extracted: ExtractedScanData,
        preparationGeneration: UUID
    ) async {
        var ownsInferenceGeneration = false
        var didDispatch = false
        defer {
            clearInferencePreparation(
                scanId: scanId,
                generation: preparationGeneration
            )
            if ownsInferenceGeneration, !didDispatch {
                finishInferenceGeneration(
                    scanId: scanId,
                    generation: preparationGeneration
                )
            }
        }
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ) else {
            return
        }
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: requested scanId=\(scanId, privacy: .public) r2Keys=\(extracted.r2Keys.count, privacy: .public)"
        )

        let existingInferenceTasks = await backgroundSession.allTasks
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ) else {
            return
        }
        if existingInferenceTasks.contains(where: { isLiveInferenceTask($0, scanId: scanId) }) {
            MerianLog.data.debug("dispatchInferenceDownloadTask: inference task already active for \(scanId, privacy: .private); skipping duplicate dispatch")
            return
        }
        guard claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: preparationGeneration
        ) != nil else {
            return
        }
        ownsInferenceGeneration = true

        // The app may have backgrounded or relaunched after the foreground body
        // reached Edge but before its response returned. Consult the durable
        // ingestion ledger before starting recovery inference so the two paths
        // cannot normally issue a second primary Gemini call. If the status
        // endpoint itself is unavailable, preserve zero-data-loss behavior by
        // allowing the queued recovery request to proceed.
        let hasScheduledServerFailureRetry =
            hasDurableScheduledServerFailureRetry(scanId: scanId)
        let serverRecovery = await recoverCompletedInferenceFromServer(
            scanId: scanId,
            reason: "pre-background-inference dispatch",
            expectedGeneration: preparationGeneration,
            reuseScheduledServerFailureRetry:
                hasScheduledServerFailureRetry
        )
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ),
              activeInferenceGenerations[scanId] == preparationGeneration else {
            return
        }
        guard Self.scanStatusActionPermitsInferenceDispatch(
            serverRecovery,
            hasScheduledServerFailureRetry:
                hasScheduledServerFailureRetry
        ) else {
            MerianLog.data.debug(
                "dispatchInferenceDownloadTask: server owns or completed scanId=\(scanId, privacy: .public); skipping duplicate inference"
            )
            return
        }

        let authenticatedRequest: AuthenticatedInferenceRequest
        do {
            authenticatedRequest = try await prepareInferenceDownloadRequestWithTimeout(
                scanId: scanId,
                extracted: extracted
            )
        } catch MerianError.aiConsentRequired {
            do {
                try ConsentManager.shared
                    .requireCurrentConsentReapprovalAfterServerRejection()
            } catch {
                MerianLog.auth.error(
                    "Queued inference consent reapproval could not be persisted; the in-memory gate remains closed: \(error.localizedDescription, privacy: .private)"
                )
            }
            MerianLog.data.debug(
                "dispatchInferenceDownloadTask: consent reapproval required before dispatch scanId=\(scanId, privacy: .private)"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: requiredConsentAttentionMessage,
                errorCode: "ai_consent_required",
                needsAttention: true
            )
            return
        } catch InferencePreparationFailure.timedOut {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: preparation timed out scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: preparationGeneration,
                reason: "pre-dispatch timeout"
            )
            return
        } catch is CancellationError {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: preparation cancelled scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: preparationGeneration,
                reason: "pre-dispatch cancelled"
            )
            return
        } catch {
            MerianLog.data.error("dispatchInferenceDownloadTask: failed to build request for \(scanId, privacy: .private): \(error, privacy: .private)")
            await handleInferenceRetry(
                scanId: scanId,
                generation: preparationGeneration,
                reason: "request build failed"
            )
            return
        }
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ),
              activeInferenceGenerations[scanId] == preparationGeneration else {
            return
        }

        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork(
                expectedUserID: authenticatedRequest.expectedAuthUserID
            ) else {
            return
        }
        var transferredAccountWorkLease = false
        defer {
            if !transferredAccountWorkLease {
                SupabaseManager.shared.finishAccountBoundWork(
                    accountWorkLease
                )
            }
        }

        // Dispatch the background download task. The OS serializes the URLRequest (including
        // httpBody) at resume() time — safe to use inline httpBody on background sessions.
        let tasksBeforeDispatch = await backgroundSession.allTasks
        guard authenticatedRequest.isBound(to: accountWorkLease.session),
              allowsAutomaticNetworkWorkOnCurrentPath,
              SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
                accountWorkLease
              ),
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ),
              activeInferenceGenerations[scanId] == preparationGeneration else {
            return
        }
        if tasksBeforeDispatch.contains(where: { isLiveInferenceTask($0, scanId: scanId) }) {
            MerianLog.data.debug("dispatchInferenceDownloadTask: inference task appeared for \(scanId, privacy: .private); skipping duplicate dispatch")
            return
        }

        let durableOwnership = BackgroundAccountWorkOwnership(
            ownerUserID: authenticatedRequest.expectedAuthUserID,
            generation: preparationGeneration,
            phase: .inference
        )
        let queueActor = resolvedQueueDbActor(
            container: extracted.container
        )
        guard await queueActor.activateBackgroundAccountWork(
            scanId: scanId,
            ownership: durableOwnership
        ) else {
            return
        }

        let task = backgroundSession.downloadTask(
            with: authenticatedRequest.request
        )
        task.taskDescription = InferenceURLSessionTaskContract.taskDescription(
            scanId: scanId,
            generation: preparationGeneration,
            ownerUserID: authenticatedRequest.expectedAuthUserID
        )
        guard SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
            accountWorkLease
        ), retainBackgroundAccountWork(
            accountWorkLease,
            for: task.taskIdentifier
        ) else {
            // Durable ownership was already moved to `.inferencing`, but this
            // unresumed task is not guaranteed to receive a terminal delegate
            // callback. Requeue it before cancellation so relaunch cannot find
            // a permanently stranded inference owner.
            let didRetire = await Self.awaitDurableBackgroundWorkRetirement(
                retire: {
                    await self.retireRejectedBackgroundAccountWork(
                        scanId: scanId,
                        generation: preparationGeneration,
                        ownerUserID:
                            authenticatedRequest.expectedAuthUserID,
                        phase: .inference
                    )
                },
                waitBeforeRetry: {
                    await Self
                        .waitForDurableBackgroundWorkRetirementRetry()
                }
            )
            if didRetire {
                task.cancel()
            }
            return
        }
        transferredAccountWorkLease = true
        inferenceDispatchDates[scanId] = Date()
        didDispatch = true
        task.resume()
        scheduleInferenceStatusProbe(
            scanId: scanId,
            generation: preparationGeneration
        )

        MerianLog.data.debug("🚀 BACKGROUND INFERENCE: Dispatched download task for \(scanId, privacy: .public)")
    }

    private func prepareInferenceDownloadRequestWithTimeout(
        scanId: String,
        extracted: ExtractedScanData
    ) async throws -> AuthenticatedInferenceRequest {
        let preparationTask = Task { @MainActor in
            try await self.buildInferenceDownloadRequest(scanId: scanId, extracted: extracted)
        }

        defer {
            preparationTask.cancel()
        }

        return try await withThrowingTaskGroup(
            of: AuthenticatedInferenceRequest.self
        ) { group in
            group.addTask {
                try await preparationTask.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                preparationTask.cancel()
                throw InferencePreparationFailure.timedOut
            }

            guard let request = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return request
        }
    }

    private func buildInferenceDownloadRequest(
        scanId: String,
        extracted: ExtractedScanData
    ) async throws -> AuthenticatedInferenceRequest {
        let baseTelemetry = extracted.telemetry

        // Background replay must never make the scan library wait on WeatherKit or geocoding.
        // The queued scan already has the R2 media keys needed for identification; optional
        // weather can be absent without blocking inference request construction.
        let hasWeatherBackfillCandidate = baseTelemetry.weatherCondition == nil
            && baseTelemetry.gpsLatitude != nil
            && baseTelemetry.gpsLongitude != nil
        let shouldFetchWeatherBackfill = false

        var finalTelemetry = baseTelemetry
        if hasWeatherBackfillCandidate && !shouldFetchWeatherBackfill {
            MerianLog.data.debug(
                "dispatchInferenceDownloadTask: skipping weather backfill during background replay scanId=\(scanId, privacy: .public)"
            )
        }
        if shouldFetchWeatherBackfill && hasWeatherBackfillCandidate {
            let ctx = await EnvironmentContextManager.shared.fetchHistoricalContext(
                location: CLLocation(latitude: baseTelemetry.gpsLatitude!, longitude: baseTelemetry.gpsLongitude!),
                date: extracted.originalTimestamp
            )
            MerianLog.data.debug("Hydrated offline scan with historical weather: \(ctx.weatherCondition ?? "none", privacy: .public)")
            finalTelemetry = CaptureTelemetry(
                subjectDistanceInMeters: baseTelemetry.subjectDistanceInMeters,
                gpsLatitude: baseTelemetry.gpsLatitude,
                gpsLongitude: baseTelemetry.gpsLongitude,
                gpsElevation: baseTelemetry.gpsElevation,
                locationName: baseTelemetry.locationName ?? ctx.locationName,
                weatherCondition: ctx.weatherCondition,
                weatherTemperatureF: ctx.weatherTemperature,
                timeOfDay: baseTelemetry.timeOfDay,
                timestamp: baseTelemetry.timestamp
            )

            let hasBackfill = ctx.weatherCondition != nil
                || ctx.weatherTemperature != nil
                || ctx.locationName != nil
            if hasBackfill {
                let container = extracted.container
                Task {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    await dbActor.updateScanTelemetry(
                        scanId: scanId,
                        weatherCondition: ctx.weatherCondition,
                        weatherTemperatureF: ctx.weatherTemperature,
                        locationName: ctx.locationName
                    )
                }
            } else {
                MerianLog.data.debug(
                    "dispatchInferenceDownloadTask: skipping empty weather backfill scanId=\(scanId, privacy: .public)"
                )
            }
        }

        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: building request scanId=\(scanId, privacy: .public)"
        )

        // All scans natively route through the unified /identify-multimodal endpoint,
        // securely supporting arrays over legacy properties.
        let audioPaths = extracted.audioFilePaths ?? []
        let videoPaths = extracted.videoFilePaths ?? []
        let stagedKeys = MediaStagingContract.splitObjectKeys(
            extracted.r2Keys,
            scanId: scanId,
            localImagePaths: extracted.localImagePaths,
            localAudioPaths: audioPaths,
            localVideoPaths: videoPaths
        )
        let visualMediaItems = extracted.visualMediaItems
        let validVisualMediaItems = visualMediaItems?.count == extracted.localImagePaths.count
            ? visualMediaItems
            : nil
        let videoFrameCount = validVisualMediaItems?
            .filter { $0.kind == .videoFrame }
            .count ?? (videoPaths.isEmpty ? nil : extracted.localImagePaths.count)
        let request = try await MerianNetworkClient.shared.buildMultiModalRequest(
            r2ObjectKeys: stagedKeys.imageR2ObjectKeys,
            audioR2ObjectKeys: stagedKeys.audioR2ObjectKeys,
            videoR2ObjectKeys: stagedKeys.videoR2ObjectKeys,
            base64ImageDatas: [], // Uploads rely purely on references through R2 object keys.
            audioFilePaths: stagedKeys.audioR2ObjectKeys.isEmpty ? audioPaths : [],
            videoFrameCount: videoFrameCount,
            visualMediaItems: validVisualMediaItems,
            audioMediaItems: extracted.audioMediaItems,
            ownerMediaTimeline: extracted.ownerMediaTimeline,
            observationContextsJSON: extracted.observationContextsJSON ?? [],
            telemetry: finalTelemetry,
            clientScanId: scanId,
            preferredGoal: extracted.preferredGoal
        )
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: built request scanId=\(scanId, privacy: .public) imageKeys=\(stagedKeys.imageR2ObjectKeys.count, privacy: .public) audioKeys=\(stagedKeys.audioR2ObjectKeys.count, privacy: .public) videoKeys=\(stagedKeys.videoR2ObjectKeys.count, privacy: .public)"
        )
        return request
    }

    // MARK: - Inference Result Processing

    /// Processes the JSON file delivered by a completed background inference download task.
    ///
    /// Mirrors the success/failure routing of the former `runInferencePipeline`:
    /// - exact handler-owned policy rejection → terminal tombstone
    /// - consent rejection → preserve media and return to required disclosure
    /// - other handler-owned HTTP 4xx → preserve media for retry/cancel
    /// - Supabase platform route 404 / HTTP 5xx / missing data → durable retry
    /// - HTTP 200 → persist `LocalScanRecord`, delete `OfflineQueuedScan`, fire notifications
    func processInferenceDownloadResult(
        scanId: String,
        generation proposedGeneration: UUID?,
        resultFileURL: URL,
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence? = nil
    ) async {
        defer { try? FileManager.default.removeItem(at: resultFileURL) }
        guard let generation = claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: proposedGeneration
        ) else {
            MerianLog.data.debug(
                "processInferenceDownloadResult: ignored stale result scanId=\(scanId, privacy: .public)"
            )
            return
        }
        defer {
            finishInferenceGeneration(scanId: scanId, generation: generation)
        }

        inferenceCompletionGenerations[scanId] = generation
        defer {
            if inferenceCompletionGenerations[scanId] == generation {
                inferenceCompletionGenerations[scanId] = nil
            }
            MerianLog.data.debug(
                "processInferenceDownloadResult: cleared inference completion lock scanId=\(scanId, privacy: .public)"
            )
        }
        cancelInferenceStatusProbe(
            scanId: scanId,
            generation: generation
        )
        MerianLog.data.debug(
            "processInferenceDownloadResult: scanId=\(scanId, privacy: .public) status=\(statusCode ?? -1, privacy: .public) file=\(resultFileURL.path, privacy: .public)"
        )

        let resultData = try? Data(contentsOf: resultFileURL)
        let responseDisposition = Self.backgroundInferenceResponseDisposition(
            statusCode: statusCode,
            functionRouteEvidence: functionRouteEvidence,
            responseData: resultData ?? Data()
        )

        switch responseDisposition {
        case .success:
            break
        case .retry:
            let code = statusCode ?? 0
            MerianLog.data.debug(
                "Background inference returned a retryable response [\(code)] for \(scanId, privacy: .private) — preserving scan."
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Retryable inference response",
                minimumRetryDelay: functionRouteEvidence?.retryAfterSeconds
            )
            return
        case .consentRequired:
            do {
                try ConsentManager.shared
                    .requireCurrentConsentReapprovalAfterServerRejection()
            } catch {
                MerianLog.auth.error(
                    "Background inference consent reapproval could not be persisted; the in-memory gate remains closed: \(error.localizedDescription, privacy: .private)"
                )
            }
            MerianLog.data.debug(
                "Background inference requires consent reapproval for \(scanId, privacy: .private) — preserving queued media."
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: requiredConsentAttentionMessage,
                errorCode: "ai_consent_required",
                httpStatus: statusCode,
                needsAttention: true
            )
            return
        case .needsAttention:
            let code = statusCode ?? 0
            if statusCode == 402 {
                EntitlementManager.shared
                    .invalidateComplimentaryProofAfterPaymentRequired()
                await EntitlementManager.shared.refreshCurrentSession()
            }
            MerianLog.data.debug(
                "Background inference needs user attention [\(code)] for \(scanId, privacy: .private) — preserving queued media."
            )
            await MainActor.run {
                _ = OfflineQueueManager.shared.softDeleteQueuedScan(
                    scanId: scanId,
                    reason: "We couldn’t process this queued observation. Please retry it or cancel it.",
                    errorCode: EdgeFunctionErrorPolicy.stableCode(
                        responseData: resultData ?? Data()
                    ) ?? "inference_http_\(code)",
                    httpStatus: statusCode,
                    needsAttention: true
                )
            }
            return
        case .terminal:
            let code = statusCode ?? 0
            MerianLog.data.debug(
                "Background inference was rejected by policy [\(code)] for \(scanId, privacy: .private)."
            )
            await MainActor.run {
                _ = OfflineQueueManager.shared.softDeleteQueuedScan(
                    scanId: scanId,
                    reason: "We couldn’t process this observation. Please try a different photo or recording.",
                    errorCode: "observation_rejected",
                    httpStatus: statusCode,
                    needsAttention: false
                )
            }
            return
        }

        guard let resultData, !resultData.isEmpty else {
            MerianLog.data.error("Background inference download: result file unreadable for \(scanId, privacy: .private)")
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "empty response file"
            )
            return
        }

        // Fetch the scan from SwiftData to read its current telemetry (may include weather
        // backfill persisted by dispatchInferenceDownloadTask before app suspension).
        let extracted: ExtractedScanData? = await MainActor.run {
            guard let context = OfflineQueueManager.shared.modelContext else { return nil }
            let container = context.container
            var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            guard let scan = (try? context.fetch(descriptor))?.first else { return nil }
            return OfflineQueueManager.shared.buildExtractedScanData(from: scan, container: container)
        }

        guard let extracted else {
            // Scan was already cleaned up (e.g., live path completed first). Nothing to do.
            MerianLog.data.debug("Background inference: scan \(scanId, privacy: .private) already removed — skipping cleanup")
            return
        }

        let pipelineStart = CFAbsoluteTimeGetCurrent()
        await MainActor.run {
            SyncStateManager.shared.beginFinalizing(generation: generation)
        }

        // Use a fresh actor so a failed atomic save doesn't corrupt the shared actor's context.
        let cleanupActor = BackgroundDatabaseActor(modelContainer: extracted.container)
        let processingResult = await cleanupActor.processAndCleanupOfflineScan(
            resultData: resultData,
            originalImagePaths: extracted.localImagePaths,
            scanId: scanId,
            originalTimestamp: extracted.originalTimestamp,
            telemetry: extracted.telemetry,
            observationContextsJSON: extracted.observationContextsJSON,
            audioFilePaths: extracted.audioFilePaths,
            videoFilePaths: extracted.videoFilePaths,
            capturedMediaJSON: extracted.capturedMediaJSON,
            expectedGeneration: generation
        )

        guard isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ) else {
            MerianLog.data.debug(
                "processInferenceDownloadResult: ownership changed during finalization scanId=\(scanId, privacy: .public)"
            )
            return
        }
        guard processingResult.wasCleaned else {
            MerianLog.data.error(
                "processInferenceDownloadResult: local persistence rejected response scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Local inference persistence did not complete"
            )
            return
        }

        // Delete the OfflineQueuedScan from the main ModelContext so @Query re-evaluates in
        // any open sheet. The background actor intentionally left it alive (see wasCleaned doc);
        // this deletion guarantees the main context has a real pending change when it saves —
        // the only reliable @Query trigger in a presented sheet (SwiftData platform limitation).
        //
        // Route through deleteQueuedScan rather than flushOfflineQueuedScan so queue-only
        // inference frames can be purged while media adopted by the final LocalScanRecord survives.
        let didDeleteQueuedScan: Bool
        let adoptedMediaPaths = processingResult.finalScanId == nil
            ? []
            : extracted.capturedMediaSnapshot.thumbnailImagePaths
                + (extracted.audioFilePaths ?? [])
                + (extracted.videoFilePaths ?? [])
        didDeleteQueuedScan = await OfflineQueueManager.shared.deleteQueuedScan(
            scanId: scanId,
            explicitlyAdoptedMediaPaths: adoptedMediaPaths,
            preservePreferredGoalHint: true,
            inferenceExpectation: InferenceGenerationExpectation(
                generation: generation
            )
        )
        guard didDeleteQueuedScan else {
            MerianLog.data.error(
                "processInferenceDownloadResult: durable result saved but queue cleanup failed scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Completed inference queue cleanup did not commit"
            )
            return
        }

        if let speciesName = processingResult.resolvedSpeciesName,
           let dbScanId = processingResult.finalScanId {
            MerianLog.data.debug(
                "processInferenceDownloadResult: finalized scanId=\(scanId, privacy: .private) dbScanId=\(dbScanId, privacy: .private) species=\(speciesName, privacy: .private)"
            )
            let capturedContainer = extracted.container
            await MainActor.run {
                // Only set the badge when the insight sheet is not already open.
                // If suppressInferenceBanners is true the user is viewing results in the
                // sheet — the badge would appear and immediately need clearing on dismiss.
                if !AppSettings.shared.suppressInferenceBanners {
                    AppSettings.shared.hasUnseenScan = true
                    AppIconBadgeCoordinator.updateAppIconBadge()
                }
                if processingResult.isNewDiscovery {
                    GamificationManager.shared.recordNewSpeciesDiscovered()
                }
                if AppSettings.shared.isPushNotificationsEnabled {
                    PushNotificationManager.shared.sendInferenceCompleteNotification(speciesName: speciesName, scanId: dbScanId)
                }
                Task {
                    await AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(
                        scanId: dbScanId,
                        speciesData: processingResult.speciesData,
                        modelContainer: capturedContainer,
                        preferredGoal: extracted.preferredGoal
                    )
                }

                // If the background path completed the same scan the live InferenceEngine is
                // currently processing, hydrate the engine directly. This fixes the case where
                // the user backgrounds the app immediately after capture: the live inference Task
                // is suspended (no BackgroundTaskWrapper protects it), the background URLSession
                // path races ahead and wins, but isProcessing stays true — leaving the insight
                // sheet in "Analyzing..." until the live task eventually times out and shows
                // "Network timeout" even though the scan completed successfully.
                //
                // The recovered-result commit first invalidates the exact live
                // presentation slot and publishes species data. Cooperative
                // cancellation happens afterward, so the old task's defer and
                // error handlers fail their generation check and become no-ops.
                if let speciesData = processingResult.speciesData {
                    let engine = AppDIContainer.shared.inferenceEngine
                    // Hydrate when the engine is still waiting for a result for this exact scan.
                    // `isProcessing` covers the case where the live path is still in flight.
                    // `engine.speciesData?.scanId == nil` covers the case where the live path
                    // already failed (timeout/network error) — those placeholders have scanId = nil.
                    // We must NOT overwrite a successful live result (speciesData.scanId != nil).
                    if engine.activeScanId == scanId,
                       engine.isProcessing || engine.speciesData?.scanId == nil,
                       let presentationGeneration =
                           engine.activeLiveInferenceAttemptGeneration {
                        let releasedForegroundGeneration =
                            engine.activeForegroundInferenceGeneration
                        let didHydrate =
                            engine.commitRecoveredBackgroundResult(
                                for: scanId,
                                replacingAttemptGeneration:
                                    presentationGeneration,
                                expectedForegroundGeneration:
                                    releasedForegroundGeneration,
                                speciesData: speciesData
                            )
                        if didHydrate {
                            engine.inferenceTask?.cancel()
                        }
                    } else if engine.commitRecoveredQueuedResult(
                        for: scanId,
                        speciesData: speciesData
                    ) {
                        engine.inferenceTask?.cancel()
                    }
                }
            }
        }

        guard isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ) else {
            MerianLog.data.debug(
                "processInferenceDownloadResult: skipped stale post-finalization state scanId=\(scanId, privacy: .public)"
            )
            return
        }
        MerianLog.data.debug("⏱️ Background pipeline total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
        await MainActor.run {
            CircuitBreakerManager.shared.recordSuccess()
        }
    }

    static func shouldRetryBackgroundInferenceRouteFailure(
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence?,
        responseData: Data
    ) -> Bool {
        guard statusCode == 404,
              let functionRouteEvidence else {
            return false
        }
        return EdgeFunctionRoutePolicy.isUnavailable(
            evidence: functionRouteEvidence,
            responseData: responseData
        )
    }

    static func backgroundInferenceResponseDisposition(
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence?,
        responseData: Data
    ) -> BackgroundInferenceResponseDisposition {
        guard let statusCode else {
            return .retry
        }
        if statusCode == 200 {
            guard !responseData.isEmpty,
                  let wrapper = try? JSONDecoder().decode(
                      EdgeResponseWrapper.self,
                      from: responseData
                  ),
                  IdentifySuccessEnvelopeValidator.isUsable(wrapper) else {
                return .retry
            }
            return .success
        }
        if shouldRetryBackgroundInferenceRouteFailure(
            statusCode: statusCode,
            functionRouteEvidence: functionRouteEvidence,
            responseData: responseData
        ) {
            return .retry
        }
        if statusCode >= 500
            || [401, 408, 409, 425, 429].contains(statusCode) {
            return .retry
        }
        if statusCode == 403,
           EdgeFunctionErrorPolicy.stableCode(responseData: responseData)
            == "ai_consent_required" {
            return .consentRequired
        }
        if statusCode == 400,
           EdgeFunctionErrorPolicy.stableCode(responseData: responseData)
            == "observation_rejected" {
            return .terminal
        }
        if (400...499).contains(statusCode) {
            return .needsAttention
        }
        return .retry
    }

    static func requiresMediaRestagingAfterServerFailure(
        _ response: ScanStatusResponse
    ) -> Bool {
        guard response.status == .notFound,
              response.jobStatus == .failedRetryable else {
            return false
        }
        switch response.jobStage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "background_ingestion_failed",
             "media_finalization_failed",
             "identity_merge_interrupted",
             "video_promotion_failed",
             "scan_insert_started":
            return true
        default:
            return false
        }
    }

    // MARK: - Inference Failure Handling

    static func scanStatusRecoveryAction(
        for response: ScanStatusResponse,
        now: Date = Date(),
        defaultPollDelay: TimeInterval = 15,
        defaultRetryDelay: TimeInterval = 30
    ) -> ScanStatusRecoveryAction {
        if response.isFound {
            return .recovered
        }

        func boundedDelay(from isoString: String?, fallback: TimeInterval) -> TimeInterval {
            guard let isoString,
                  let date = Self.parseRetryAfterDate(isoString) else {
                return fallback
            }
            return min(max(date.timeIntervalSince(now), 1), 300)
        }

        switch response.jobStatus {
        case .processing, .finalizing:
            return .waitForServer(boundedDelay(from: response.retryAfter, fallback: defaultPollDelay))
        case .retrying:
            return .waitForServer(boundedDelay(from: response.retryAfter, fallback: defaultRetryDelay))
        case .failedRetryable:
            return .retryAfter(boundedDelay(from: response.retryAfter, fallback: defaultRetryDelay))
        case .failed:
            return .terminalFailure(response.lastError)
        case .complete, nil:
            return .unresolved
        }
    }

    /// A retryable server failure first writes a generation-fenced local retry.
    /// Once that durable marker survives its delay (and any required media
    /// restaging), the next exact-generation preflight must be allowed to send
    /// the identify request that can reclaim the backend attempt. Treating that
    /// same status as server-owned again creates a status/upload loop with no
    /// provider request.
    static func scanStatusActionPermitsInferenceDispatch(
        _ action: ScanStatusRecoveryAction,
        hasScheduledServerFailureRetry: Bool
    ) -> Bool {
        switch action {
        case .unresolved:
            true
        case .retryAfter:
            hasScheduledServerFailureRetry
        case .recovered, .waitForServer, .terminalFailure:
            false
        }
    }

    private func scheduleInferenceStatusProbe(
        scanId: String,
        generation: UUID
    ) {
        inferenceStatusProbeTasks.replace(
            for: scanId,
            ownerGeneration: generation
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    _ = self.inferenceStatusProbeTasks.clearIfCurrent(
                        scanId,
                        token: token
                    )
                }

                // Cumulative ~105s: longer than the 90s inference request timeout, so the
                // watchdog only fires when URLSession did not deliver either success or failure.
                let delays: [Duration] = [.seconds(10), .seconds(30), .seconds(65)]
                for delay in delays {
                    do {
                        try await Task.sleep(for: delay)
                    } catch {
                        return
                    }
                    guard self.inferenceStatusProbeTasks.isCurrent(
                        scanId,
                        token: token,
                        ownerGeneration: generation
                    ),
                    self.activeInferenceGenerations[scanId] == generation,
                    self.allowsAutomaticNetworkWorkOnCurrentPath else {
                        return
                    }

                    let recovered = await self.recoverCompletedInferenceFromServer(
                        scanId: scanId,
                        reason: "delayed probe",
                        expectedGeneration: generation
                    )
                    if recovered != .unresolved {
                        guard self.inferenceStatusProbeTasks.isCurrent(
                            scanId,
                            token: token,
                            ownerGeneration: generation
                        ),
                        self.activeInferenceGenerations[scanId] == generation else {
                            return
                        }
                        let cancelledCount = await self.cancelActiveInferenceTasks(
                            scanId: scanId,
                            generation: generation
                        )
                        guard self.activeInferenceGenerations[scanId] == generation else {
                            return
                        }
                        guard self.inferenceStatusProbeTasks.clearIfCurrent(
                            scanId,
                            token: token
                        ) else {
                            return
                        }
                        self.finishInferenceGeneration(
                            scanId: scanId,
                            generation: generation
                        )
                        MerianLog.data.debug(
                            "scheduleInferenceStatusProbe: server assumed ownership scanId=\(scanId, privacy: .public) cancelledTasks=\(cancelledCount, privacy: .public)"
                        )
                        return
                    }

                    guard self.inferenceStatusProbeTasks.isCurrent(
                        scanId,
                        token: token,
                        ownerGeneration: generation
                    ),
                    self.activeInferenceGenerations[scanId] == generation else {
                        return
                    }

                    let activeTaskCount = await self.activeInferenceTaskCount(
                        scanId: scanId,
                        generation: generation
                    )
                    MerianLog.data.debug(
                        "scheduleInferenceStatusProbe: scan still pending scanId=\(scanId, privacy: .public) activeTasks=\(activeTaskCount, privacy: .public)"
                    )
                }

                guard self.inferenceStatusProbeTasks.isCurrent(
                    scanId,
                    token: token,
                    ownerGeneration: generation
                ),
                self.activeInferenceGenerations[scanId] == generation else {
                    return
                }

                let elapsed = self.inferenceDispatchDates[scanId]
                    .map { Date().timeIntervalSince($0) } ?? -1
                MerianLog.data.debug(
                    "scheduleInferenceStatusProbe: watchdog firing scanId=\(scanId, privacy: .public) elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s"
                )

                let cancelledCount = await self.cancelActiveInferenceTasks(
                    scanId: scanId,
                    generation: generation
                )
                guard self.inferenceStatusProbeTasks.clearIfCurrent(
                    scanId,
                    token: token
                ),
                self.activeInferenceGenerations[scanId] == generation else {
                    return
                }
                self.finishInferenceGeneration(
                    scanId: scanId,
                    generation: generation
                )
                MerianLog.data.debug(
                    "scheduleInferenceStatusProbe: cancelled hung inference tasks scanId=\(scanId, privacy: .public) count=\(cancelledCount, privacy: .public)"
                )

                guard self.activeInferenceGenerations[scanId] == nil else { return }
                await self.handleInferenceRetry(
                    scanId: scanId,
                    generation: nil,
                    reason: "watchdog"
                )
            }
        }
        MerianLog.data.debug("scheduleInferenceStatusProbe: scheduled scanId=\(scanId, privacy: .public)")
    }

    private func cancelInferenceStatusProbe(
        scanId: String,
        generation: UUID
    ) {
        inferenceStatusProbeTasks.cancel(
            scanId,
            ifOwnedBy: generation
        )
        if activeInferenceGenerations[scanId] == generation {
            inferenceDispatchDates[scanId] = nil
        }
        MerianLog.data.debug("cancelInferenceStatusProbe: cancelled scanId=\(scanId, privacy: .public)")
    }

    private func clearServerIngestionState(
        scanId: String,
        preservingPollToken: UUID? = nil
    ) {
        if preservingPollToken == nil {
            serverIngestionPollTasks.cancel(scanId)
        }
        scanIngestionJobStates[scanId] = nil
    }

    private func isServerIngestionPollCurrent(
        scanId: String,
        token: UUID?
    ) -> Bool {
        guard let token else { return true }
        return serverIngestionPollTasks.isCurrent(
            scanId,
            token: token
        )
    }

    private func scheduleServerIngestionPoll(
        scanId: String,
        delay: TimeInterval,
        reason: String
    ) {
        serverIngestionPollTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    _ = self.serverIngestionPollTasks.clearIfCurrent(
                        scanId,
                        token: token
                    )
                }
                let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard self.serverIngestionPollTasks.isCurrent(
                    scanId,
                    token: token
                ),
                self.activeInferenceGenerations[scanId] == nil,
                self.allowsAutomaticNetworkWorkOnCurrentPath else {
                    return
                }
                await self.handleInferenceRetry(
                    scanId: scanId,
                    generation: nil,
                    reason: reason,
                    serverPollToken: token
                )
            }
        }
        MerianLog.data.debug(
            "scheduleServerIngestionPoll: scheduled scanId=\(scanId, privacy: .public) delay=\(String(format: "%.1f", delay), privacy: .public)s reason=\(reason, privacy: .public)"
        )
    }

    private func scheduleRetryableServerFailure(
        scanId: String,
        delay: TimeInterval,
        reason: String,
        expectedGeneration: UUID?,
        resetMediaUploads: Bool
    ) async {
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              let container = modelContext?.container else {
            return
        }
        let currentAttempt = queueAttemptCount(for: scanId)
        guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(
            currentAttempt: currentAttempt
        ) else {
            markQueuedScanNeedsAttention(
                scanId: scanId,
                code: "automatic_retry_limit_reached",
                message: OfflineQueueRetryPolicy.automaticRetryLimitMessage()
            )
            serverIngestionPollTasks.cancel(scanId)
            MerianLog.data.debug(
                "scheduleRetryableServerFailure: retry limit reached scanId=\(scanId, privacy: .public) attempts=\(currentAttempt, privacy: .public)"
            )
            return
        }
        let retryActor = resolvedQueueDbActor(container: container)
        guard let retries = await retryActor.scheduleInferenceRetry(
            id: scanId,
            expectedGeneration: expectedGeneration,
            code: Self.serverRetryableFailureCode,
            message: reason,
            delay: delay,
            resetMediaUploads: resetMediaUploads
        ) else {
            // Another serialized owner may already have committed the same
            // retreat, or a cloud-complete marker may have superseded it. Both
            // are expected coalescing outcomes, not an error worth repeating
            // on every library/scheduler wake.
            if hasDurableScheduledServerFailureRetry(scanId: scanId) ||
                hasDurableCompletedServerResult(scanId: scanId) {
                return
            }
            MerianLog.data.debug(
                "scheduleRetryableServerFailure: persistence generation changed scanId=\(scanId, privacy: .public)"
            )
            return
        }
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)

        serverIngestionPollTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    _ = self.serverIngestionPollTasks.clearIfCurrent(
                        scanId,
                        token: token
                    )
                }
                let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard self.serverIngestionPollTasks.isCurrent(
                    scanId,
                    token: token
                ),
                self.activeInferenceGenerations[scanId] == nil,
                self.allowsAutomaticNetworkWorkOnCurrentPath else {
                    return
                }

                guard !Task.isCancelled,
                      self.serverIngestionPollTasks.isCurrent(
                        scanId,
                        token: token
                      ),
                      self.activeInferenceGenerations[scanId] == nil else {
                    return
                }
                self.updateUnsyncedItemCount()
                if resetMediaUploads {
                    self.syncPendingScans()
                } else {
                    self.replayInferenceForUploadedScans()
                }
            }
        }
        MerianLog.data.debug(
            "scheduleRetryableServerFailure: scheduled scanId=\(scanId, privacy: .public) delay=\(String(format: "%.1f", delay), privacy: .public)s retry=\(retries, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    private func isLiveInferenceTask(_ task: URLSessionTask, scanId: String) -> Bool {
        InferenceURLSessionTaskContract.parse(task.taskDescription)?.scanId == scanId
            && task.state != .canceling
            && task.state != .completed
    }

    private func cancelActiveInferenceTasks(
        scanId: String,
        generation: UUID
    ) async -> Int {
        let tasks = await backgroundSession.allTasks
        let matchingTasks = tasks.filter {
            guard let identity = InferenceURLSessionTaskContract.parse(
                $0.taskDescription
            ) else {
                return false
            }
            return identity.scanId == scanId
                && identity.generation == generation
                && $0.state != .completed
        }
        for task in matchingTasks {
            task.cancel()
        }
        return matchingTasks.count
    }

    private func activeInferenceTaskCount(
        scanId: String,
        generation: UUID
    ) async -> Int {
        let tasks = await backgroundSession.allTasks
        return tasks.filter { task in
            guard isLiveInferenceTask(task, scanId: scanId),
                  let identity = InferenceURLSessionTaskContract.parse(
                    task.taskDescription
                  ) else {
                return false
            }
            return identity.generation == generation
        }.count
    }

    private func recoverCompletedInferenceFromServer(
        scanId: String,
        reason: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID? = nil,
        reuseScheduledServerFailureRetry: Bool = false
    ) async -> ScanStatusRecoveryAction {
        let hadDurableCompletedServerResult =
            hasDurableCompletedServerResult(scanId: scanId)
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return hadDurableCompletedServerResult
                ? .waitForServer(1)
                : .unresolved
        }
        let requiredVideoCount = requiredVideoCountForQueuedScan(scanId: scanId)
        let response: ScanStatusResponse
        do {
            response = try await MerianNetworkClient.shared.checkScanStatusDetails(
                scanId: scanId,
                requiredVideoCount: requiredVideoCount
            )
        } catch {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: status check failed scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            if hadDurableCompletedServerResult {
                return await deferCompletedServerResultRecovery(
                    scanId: scanId,
                    expectedGeneration: expectedGeneration,
                    serverPollToken: serverPollToken
                )
            }
            return .unresolved
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return response.isFound || hadDurableCompletedServerResult
                ? .waitForServer(1)
                : .unresolved
        }

        if let jobStatus = response.jobStatus {
            scanIngestionJobStates[scanId] = jobStatus
        } else {
            scanIngestionJobStates[scanId] = nil
        }
        persistServerStatus(scanId: scanId, response: response)

        let action = Self.scanStatusRecoveryAction(for: response)
        guard allowsAutomaticNetworkWorkOnCurrentPath else {
            // Keep exact completed-owner evidence persisted, but do not begin
            // another automatic network request or consume recovery budget
            // after a satisfied path becomes constrained.
            return response.isFound || hadDurableCompletedServerResult
                ? .waitForServer(1)
                : .unresolved
        }
        MerianLog.data.debug(
            "recoverCompletedInferenceFromServer: scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public) status=\(response.status.rawValue, privacy: .public) jobStatus=\((response.jobStatus?.rawValue ?? "nil"), privacy: .public) jobStage=\((response.jobStage ?? "nil"), privacy: .public) requiredVideos=\(requiredVideoCount, privacy: .public)"
        )
        if action != .recovered,
           hasDurableCompletedServerResult(scanId: scanId) {
            // A prior exact-owner `found` observation is stronger than a later
            // unavailable or temporarily inconsistent status response. Keep
            // this row server-owned and bound recovery rather than allowing a
            // second inference dispatch.
            return await deferCompletedServerResultRecovery(
                scanId: scanId,
                expectedGeneration: expectedGeneration,
                serverPollToken: serverPollToken
            )
        }
        switch action {
        case .recovered:
            let hydrationOutcome = await recoverFoundScanFromServer(
                scanId: scanId,
                reason: reason,
                expectedGeneration: expectedGeneration,
                serverPollToken: serverPollToken
            )
            switch hydrationOutcome {
            case .recovered:
                return .recovered
            case .retryable:
                return await deferCompletedServerResultRecovery(
                    scanId: scanId,
                    expectedGeneration: expectedGeneration,
                    serverPollToken: serverPollToken
                )
            case .contractMismatch:
                let didPause = markCompletedServerResultContractMismatch(
                    scanId: scanId
                )
                guard didPause else {
                    return await deferCompletedServerResultRecovery(
                        scanId: scanId,
                        expectedGeneration: expectedGeneration,
                        serverPollToken: serverPollToken
                    )
                }
                clearServerIngestionState(
                    scanId: scanId,
                    preservingPollToken: serverPollToken
                )
                return .terminalFailure(
                    Self.completedServerResultContractMismatchMessage
                )
            }
        case .waitForServer(let delay):
            scheduleServerIngestionPoll(
                scanId: scanId,
                delay: delay,
                reason: "server ingestion poll"
            )
            return action
        case .retryAfter(let delay):
            if !reuseScheduledServerFailureRetry {
                await scheduleRetryableServerFailure(
                    scanId: scanId,
                    delay: delay,
                    reason: reason,
                    expectedGeneration: expectedGeneration,
                    resetMediaUploads:
                        Self.requiresMediaRestagingAfterServerFailure(response)
                )
            } else {
                MerianLog.data.debug(
                    "recoverCompletedInferenceFromServer: exact scheduled retry is ready to reclaim failed server attempt scanId=\(scanId, privacy: .public)"
                )
            }
            return action
        case .terminalFailure(let message):
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: terminal server failure scanId=\(scanId, privacy: .public) message=\((message ?? "nil"), privacy: .public)"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: message,
                errorCode: "server_terminal_failure",
                needsAttention: true
            )
            clearServerIngestionState(
                scanId: scanId,
                preservingPollToken: serverPollToken
            )
            return action
        case .unresolved:
            return .unresolved
        }
    }

    private func recoverFoundScanFromServer(
        scanId: String,
        reason: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID?
    ) async -> CompletedServerResultHydrationOutcome {
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }
        // A server-side completion is not yet a local recovery success. Keep
        // both its latest status and persisted retry/backoff history until the
        // result has been hydrated, promoted, and the queue row has been
        // deleted. Clearing either here made a failed local sync look like a
        // fresh attempt and discarded useful recovery state.
        let targetedSyncOutcome: HistoricalScanDownOutcome
        if let context = modelContext {
            targetedSyncOutcome = await AppDIContainer.shared.scanRepository.syncHistoricalScanDown(
                scanId: scanId,
                modelContext: context
            )
        } else {
            targetedSyncOutcome = .transientFailure
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }

        guard targetedSyncOutcome != .contractMismatch else {
            MerianLog.data.error(
                "recoverCompletedInferenceFromServer: completed cloud row violates the captured-media contract scanId=\(scanId, privacy: .public)"
            )
            return .contractMismatch
        }

        var recoveredLocalRecord = promoteRecoveredLocalScan(scanId: scanId)
        if recoveredLocalRecord == nil,
           targetedSyncOutcome != .reconciled,
           let context = modelContext {
            guard allowsAutomaticNetworkWorkOnCurrentPath else {
                return .retryable
            }
            await AppDIContainer.shared.scanRepository.syncHistoricalScansDown(
                modelContext: context
            )
            guard !Task.isCancelled,
                  isServerIngestionPollCurrent(
                      scanId: scanId,
                      token: serverPollToken
                  ),
                  isInferenceGenerationCurrent(
                      scanId: scanId,
                      expectedGeneration: expectedGeneration
                  ) else {
                return .retryable
            }
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            recoveredLocalRecord = promoteRecoveredLocalScan(scanId: scanId)
        }
        guard let recoveredLocalRecord else {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: server found scan but no local record after targeted/full sync scanId=\(scanId, privacy: .public) targetedOutcome=\(String(describing: targetedSyncOutcome), privacy: .public)"
            )
            return .retryable
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }

        let didDeleteQueue = await deleteQueuedScan(
            scanId: scanId,
            preservePreferredGoalHint: true,
            inferenceExpectation: InferenceGenerationExpectation(
                generation: expectedGeneration
            ),
            serverPollTokenToPreserve: serverPollToken
        )
        guard didDeleteQueue else {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: queue deletion lost ownership or failed scanId=\(scanId, privacy: .public)"
            )
            return .retryable
        }
        await AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(
            scanId: scanId,
            speciesData: nil,
            modelContainer: modelContext?.container,
            preferredGoal: buildPreferredGoalHint(scanId: scanId)
        )
        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }
        updateUnsyncedItemCount()
        AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
        let didHydratePresentedResult =
            AppDIContainer.shared.inferenceEngine.commitRecoveredQueuedRecord(
                recoveredLocalRecord,
                for: scanId
            )
        MerianLog.data.debug(
            "recoverCompletedInferenceFromServer: recovered scanId=\(scanId, privacy: .public) targetedOutcome=\(String(describing: targetedSyncOutcome), privacy: .public) promotedLocal=true deletedQueue=\(didDeleteQueue, privacy: .public) hydratedPresentation=\(didHydratePresentedResult, privacy: .public)"
        )

        return .recovered
    }

    private func deferCompletedServerResultRecovery(
        scanId: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID?
    ) async -> ScanStatusRecoveryAction {
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            // The definitive server result still makes a second provider
            // dispatch unsafe. A replacement owner will continue recovery.
            return .waitForServer(1)
        }

        let currentAttempt = queueAttemptCount(for: scanId)
        guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(
            currentAttempt: currentAttempt
        ) else {
            let message = [
                "Naturebook found this completed analysis in the cloud but",
                "could not restore it on this device after several attempts.",
                "You can retry manually when the connection is stable."
            ].joined(separator: " ")
            markQueuedScanNeedsAttention(
                scanId: scanId,
                code: "server_result_local_recovery_exhausted",
                message: message
            )
            return .terminalFailure(message)
        }

        let delay = OfflineQueueRetryPolicy.jitteredDelay(
            forAttempt: currentAttempt + 1
        )
        let retryMessage =
            Self.completedServerResultRecoveryMessage
        if let container = modelContext?.container {
            let retryActor = resolvedQueueDbActor(container: container)
            let retries = await retryActor.scheduleServerResultRecoveryRetry(
                id: scanId,
                expectedGeneration: expectedGeneration,
                code: Self.completedServerResultRecoveryCode,
                message: retryMessage,
                delay: delay
            )
            if let retries {
                MerianLog.data.debug(
                    "deferCompletedServerResultRecovery: scheduled scanId=\(scanId, privacy: .public) retry=\(retries, privacy: .public)"
                )
                OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            } else {
                MerianLog.data.debug(
                    "deferCompletedServerResultRecovery: durable owner changed or retry save failed scanId=\(scanId, privacy: .public)"
                )
            }
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .waitForServer(delay)
        }
        scheduleServerIngestionPoll(
            scanId: scanId,
            delay: delay,
            reason: "completed cloud result local recovery"
        )
        return .waitForServer(delay)
    }

    private func requiredVideoCountForQueuedScan(scanId: String) -> Int {
        guard let context = modelContext else { return 0 }
        let readContext = ModelContext(context.container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        guard let scan = (try? readContext.fetch(descriptor))?.first else { return 0 }
        return scan.capturedMediaSnapshot.videoPaths.count
    }

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

    private func promoteRecoveredLocalScan(
        scanId: String
    ) -> LocalScanRecord? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let record: LocalScanRecord?
        do {
            record = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug(
                "promoteRecoveredLocalScan: fetch failed scanId=\(scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        guard let record else { return nil }
        if record.captureDate == nil {
            record.captureDate = record.timestamp
        }
        record.timestamp = Date()
        do {
            try context.save()
            MerianLog.data.debug("promoteRecoveredLocalScan: promoted scanId=\(scanId, privacy: .public)")
            return record
        } catch {
            context.rollback()
            MerianLog.data.error(
                "promoteRecoveredLocalScan: save failed scanId=\(scanId, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Handles a background inference download task network-level failure.
    ///
    /// Called from `urlSession(_:task:didCompleteWithError:)` when the download task fails
    /// with a transport error (the server never responded). Resets the scan to `.staged` after
    /// a persisted backoff window so app relaunches do not lose retry state.
    ///
    /// Code=-999 (NSURLErrorCancelled) is special-cased: it means an owner path explicitly
    /// cancelled the task. Either the parallel live inference path already succeeded, the user
    /// deleted the queued scan, or the inference watchdog reset the scan to `.staged`.
    func handleInferenceTaskNetworkFailure(
        scanId: String,
        generation proposedGeneration: UUID?,
        error: Error
    ) async {
        guard let generation = claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: proposedGeneration
        ) else {
            MerianLog.data.debug(
                "handleInferenceTaskNetworkFailure: ignored stale failure scanId=\(scanId, privacy: .public)"
            )
            return
        }
        defer {
            finishInferenceGeneration(scanId: scanId, generation: generation)
        }

        cancelInferenceStatusProbe(
            scanId: scanId,
            generation: generation
        )
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            MerianLog.data.debug("Background inference cancelled for \(scanId, privacy: .private) — owner path handled retry or cleanup")
            return
        }
        MerianLog.data.debug("Background inference download failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        await handleInferenceRetry(
            scanId: scanId,
            generation: generation,
            reason: "network failure"
        )
    }

    /// Records durable retry metadata for a scan after the persisted backoff
    /// window. Transient inference failures retreat to `.staged`; a definitive
    /// cloud result stays `.inferencing` and retries only owner-result recovery.
    ///
    /// Before retrying, polls `/check-scan-status` to detect the outbox gap: if the edge
    /// function already persisted the scan but the background download task never delivered
    /// the response, a naive retry would re-run inference and insert a duplicate row. When
    /// the scan is found server-side, targeted historical sync restores the `LocalScanRecord`
    /// and the queue entry is deleted.
    func handleInferenceRetry(
        scanId: String,
        generation: UUID?,
        reason: String = "retry",
        serverPollToken: UUID? = nil,
        minimumRetryDelay: TimeInterval? = nil
    ) async {
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
            scanId: scanId,
            token: serverPollToken
        ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: generation
              ) else {
            return
        }
        guard let container = modelContext?.container else { return }

        let recoveryAction = await recoverCompletedInferenceFromServer(
            scanId: scanId,
            reason: reason,
            expectedGeneration: generation,
            serverPollToken: serverPollToken
        )
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ) else {
            return
        }
        if recoveryAction != .unresolved {
            return
        }
        guard isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ) else {
            return
        }

        let currentAttempt = queueAttemptCount(for: scanId)
        guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: currentAttempt) else {
            markQueuedScanNeedsAttention(
                scanId: scanId,
                code: "automatic_retry_limit_reached",
                message: OfflineQueueRetryPolicy.automaticRetryLimitMessage()
            )
            MerianLog.data.debug(
                "Inference retry limit reached for \(scanId, privacy: .private) after \(currentAttempt, privacy: .public) attempts"
            )
            return
        }

        let delay = OfflineQueueRetryPolicy.scanRetryDelay(
            forAttempt: currentAttempt + 1,
            serverMinimumDelay: minimumRetryDelay
        )
        let retryActor = resolvedQueueDbActor(container: container)
        guard let retries = await retryActor.scheduleInferenceRetry(
            id: scanId,
            expectedGeneration: generation,
            code: "inference_retry",
            message: reason,
            delay: delay
        ) else {
            MerianLog.data.debug(
                "handleInferenceRetry: persistence generation changed scanId=\(scanId, privacy: .public)"
            )
            return
        }
        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: generation
              ) else {
            return
        }
        MerianLog.data.debug("Inference failed for \(scanId, privacy: .private) — scheduled durable retry \(retries, privacy: .public) reason=\(reason, privacy: .private)")
        updateUnsyncedItemCount()
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        inferenceRetryTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard self.inferenceRetryTasks.clearIfCurrent(
                    scanId,
                    token: token
                ),
                self.activeInferenceGenerations[scanId] == nil else {
                    return
                }
                self.replayInferenceForUploadedScans()
            }
        }
    }
}
