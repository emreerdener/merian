import Foundation
import SwiftData

private let backgroundAccountWorkQuiescenceTimeout: Duration = .seconds(30)

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

    /// Restores a rejected transport's durable queue owner before any caller
    /// invalidates its generation or cancels its unresumed URLSession task.
    /// Shared only by terminal routing and inference dispatch.
    func retireRejectedBackgroundAccountWork(
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
                if didPersistRetirement,
                   ownership.phase == .inference {
                    finishInferenceGeneration(
                        scanId: candidate.scanId,
                        generation: ownership.generation
                    )
                }
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
                            finishInferenceGeneration(
                                scanId: identity.scanId,
                                generation: generation
                            )
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
