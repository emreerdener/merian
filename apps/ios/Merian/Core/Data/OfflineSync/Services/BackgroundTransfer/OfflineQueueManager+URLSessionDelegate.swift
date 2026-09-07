import Foundation

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
