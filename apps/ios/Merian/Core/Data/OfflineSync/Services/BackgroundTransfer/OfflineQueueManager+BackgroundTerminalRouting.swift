import Foundation

extension OfflineQueueManager {
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
                finishInferenceGeneration(
                    scanId: scanId,
                    generation: generation
                )
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
                finishInferenceGeneration(
                    scanId: scanId,
                    generation: generation
                )
            }
            return
        }
        await handleInferenceTaskNetworkFailure(
            scanId: scanId,
            generation: generation,
            error: error
        )
    }
}
