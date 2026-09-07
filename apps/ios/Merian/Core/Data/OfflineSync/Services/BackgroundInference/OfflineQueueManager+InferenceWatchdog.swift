import Foundation

// MARK: - Background Inference Watchdog

extension OfflineQueueManager {
    func scheduleInferenceStatusProbe(
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
                        guard self.inferenceStatusProbeTasks.isCurrent(
                            scanId,
                            token: token,
                            ownerGeneration: generation
                        ),
                        self.activeInferenceGenerations[scanId] == generation else {
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
                guard self.inferenceStatusProbeTasks.isCurrent(
                    scanId,
                    token: token,
                    ownerGeneration: generation
                ),
                self.activeInferenceGenerations[scanId] == generation else {
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

    func isLiveInferenceTask(_ task: URLSessionTask, scanId: String) -> Bool {
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
}
