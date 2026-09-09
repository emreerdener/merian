import Foundation
import Testing

@Suite("Offline Queue Background Inference Architecture")
struct BackgroundInferenceArchitectureTests {
    @Test func focusedFilesAndDeclarationsHaveExactOwners() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)
        let serviceRoot = root.appendingPathComponent(
            "Services/BackgroundInference"
        )
        let focusedPaths = try swiftFiles(below: serviceRoot).map {
            relativePath(of: $0, below: root)
        } + [Self.policyPath]

        #expect(Set(focusedPaths) == Set(Self.expectedImportsByPath.keys))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                Self.retiredAggregatePath
            ).path
        ))

        for (declaration, expectedPath) in Self.declarationOwners {
            let owners = try sources.compactMap { file -> String? in
                let source = try contents(of: file)
                guard containsDeclaration(declaration, in: source) else {
                    return nil
                }
                return relativePath(of: file, below: root)
            }
            #expect(owners == [expectedPath])
        }
    }

    @Test func focusedFilesStayBoundedAndDependencyFocused() throws {
        let root = try offlineSyncRoot()

        for (path, expectedImports) in Self.expectedImportsByPath {
            let source = try source(path, below: root)
            #expect(
                lineCount(of: source) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
            #expect(
                imports(in: source) == expectedImports,
                "\(path) has an unexpected framework dependency"
            )
        }

    }

    @Test func focusedInferenceResponsibilitiesStaySeparated() throws {
        let root = try offlineSyncRoot()
        let lifecycle = try source(Self.lifecyclePath, below: root)
        let dispatch = try source(Self.dispatchPath, below: root)
        let completion = try source(Self.completionPath, below: root)
        let finalization = try source(Self.finalizationPath, below: root)
        let watchdog = try source(Self.watchdogPath, below: root)
        let recovery = try source(Self.recoveryPath, below: root)
        let reconciliation = try source(
            Self.reconciliationPath,
            below: root
        )
        let retry = try source(Self.retryPath, below: root)
        let policy = try source(Self.policyPath, below: root)
        let durability = try source(Self.durabilityPath, below: root)

        #expect(lifecycle.contains("func claimInferenceGeneration("))
        #expect(lifecycle.contains("func isInferenceGenerationCurrent("))
        #expect(lifecycle.contains("func finishInferenceGeneration("))
        #expect(lifecycle.contains("activeInferenceGenerations["))
        #expect(!lifecycle.contains("URLSession"))
        #expect(!lifecycle.contains("MerianNetworkClient"))
        #expect(!lifecycle.contains("SupabaseManager"))
        #expect(!lifecycle.contains("import SwiftData"))

        #expect(dispatch.contains("enum BackgroundInferencePreparationRace"))
        #expect(dispatch.contains("func dispatchInferenceDownloadTask("))
        #expect(dispatch.contains(
            "private func prepareInferenceDownloadRequestWithTimeout("
        ))
        #expect(dispatch.contains(
            "private func buildInferenceDownloadRequest("
        ))
        #expect(dispatch.contains("backgroundSession.downloadTask("))
        #expect(dispatch.contains("task.resume()"))
        #expect(!dispatch.contains("activeInferenceGenerations["))
        #expect(!dispatch.contains("import SwiftData"))

        #expect(completion.contains("func processInferenceDownloadResult("))
        #expect(completion.contains(
            "func handleInferenceTaskNetworkFailure("
        ))
        #expect(completion.contains(
            "private func cancelInferenceStatusProbe("
        ))
        #expect(completion.contains("processAndCleanupOfflineScan("))
        #expect(completion.contains("deleteQueuedScan("))
        #expect(!completion.contains("MerianNetworkClient"))
        #expect(!completion.contains("backgroundSession"))
        #expect(!completion.contains("func handleInferenceRetry("))
        #expect(!completion.contains("func recoverCompletedInferenceFromServer("))
        #expect(!completion.contains(
            "weather backfill persisted by dispatchInferenceDownloadTask"
        ))

        #expect(finalization.contains(
            "struct BackgroundInferenceFinalizationService"
        ))
        #expect(finalization.contains("func processAndCleanupOfflineScan("))
        #expect(finalization.contains(
            "InferenceResponsePreparationService.live.prepare("
        ))
        #expect(finalization.contains(
            "persistOfflineScanResultAssumingPersistenceLock("
        ))
        #expect(finalization.contains(
            "ScanInferencePersistenceCoordinator.shared.acquire("
        ))
        #expect(finalization.contains(
            "ScanInferencePersistenceCoordinator.shared.release("
        ))
        #expect(!finalization.contains("import SwiftData"))
        #expect(!finalization.contains("JSONDecoder"))
        #expect(!finalization.contains("EntitlementManager"))
        #expect(!finalization.contains("modelContext"))

        #expect(watchdog.contains("func scheduleInferenceStatusProbe("))
        #expect(watchdog.contains("func isLiveInferenceTask("))
        #expect(watchdog.contains(
            "private func cancelActiveInferenceTasks("
        ))
        #expect(watchdog.contains(
            "private func activeInferenceTaskCount("
        ))
        #expect(watchdog.contains("backgroundSession.allTasks"))
        #expect(!watchdog.contains("MerianNetworkClient"))
        #expect(!watchdog.contains("import SwiftData"))
        #expect(!watchdog.contains("task.resume()"))

        #expect(recovery.contains(
            "enum CompletedServerResultHydrationOutcome"
        ))
        #expect(recovery.contains(
            "func recoverCompletedInferenceFromServer("
        ))
        #expect(recovery.contains("func recoverFoundScanFromServer("))
        #expect(recovery.contains("MerianNetworkClient.shared"))
        #expect(recovery.contains("AppDIContainer.shared.scanRepository"))
        #expect(!recovery.contains("backgroundSession"))

        #expect(reconciliation.contains(
            "func serverOwnedInferencingScanIds("
        ))
        #expect(reconciliation.contains(
            "recoverCompletedInferenceFromServer("
        ))
        #expect(!reconciliation.contains("MerianNetworkClient"))
        #expect(!reconciliation.contains("import SwiftData"))

        #expect(retry.contains("func isServerIngestionPollCurrent("))
        #expect(retry.contains("func scheduleServerIngestionPoll("))
        #expect(retry.contains("func handleInferenceRetry("))
        #expect(retry.contains("serverIngestionPollTasks.replace("))
        #expect(retry.contains("inferenceRetryTasks.replace("))
        #expect(!retry.contains("MerianNetworkClient"))
        #expect(!retry.contains("AppDIContainer"))
        #expect(!retry.contains("import SwiftData"))

        #expect(policy.contains("enum BackgroundInferencePolicy"))
        #expect(!policy.contains("extension OfflineQueueManager"))
        #expect(!policy.contains("@MainActor"))
        #expect(policy.contains("static func scanStatusRecoveryAction("))
        #expect(policy.contains(
            "static func backgroundInferenceResponseDisposition("
        ))
        #expect(!policy.contains(".shared"))
        #expect(!policy.contains("URLSession"))
        #expect(!policy.contains("SwiftData"))
        #expect(!policy.contains("activeInferenceGenerations"))
        #expect(durability.contains(
            "BackgroundInferencePolicy.parseRetryAfterDate"
        ))
        #expect(!durability.contains("Self.parseRetryAfterDate"))

    }

    @Test func completionPreservesGenerationAndPersistenceOrdering() throws {
        let root = try offlineSyncRoot()
        let completion = try source(Self.completionPath, below: root)
        let failureMarker = try #require(completion.range(
            of: "// MARK: - Inference Task Failure"
        ))
        let result = String(completion[..<failureMarker.lowerBound])
        let failure = String(completion[failureMarker.upperBound...])

        let resultFileCleanup = try #require(result.range(
            of: "defer { try? FileManager.default.removeItem(at: resultFileURL) }"
        ))
        let claim = try #require(result.range(
            of: "guard let generation = claimInferenceGeneration("
        ))
        let completionFence = try #require(result.range(
            of: "inferenceCompletionGenerations[scanId] = generation"
        ))
        let compareBeforeClear = try #require(result.range(
            of: "if inferenceCompletionGenerations[scanId] == generation"
        ))
        let completionClear = try #require(result.range(
            of: "inferenceCompletionGenerations[scanId] = nil"
        ))
        let durableFinalization = try #require(result.range(
            of: "processAndCleanupOfflineScan("
        ))
        let ownershipRevalidation = try #require(result.range(
            of: "guard isInferenceGenerationCurrent("
        ))
        let queueDeletion = try #require(result.range(
            of: "didDeleteQueuedScan = await OfflineQueueManager.shared.deleteQueuedScan("
        ))

        #expect(resultFileCleanup.lowerBound < claim.lowerBound)
        #expect(claim.lowerBound < completionFence.lowerBound)
        #expect(completionFence.lowerBound < compareBeforeClear.lowerBound)
        #expect(compareBeforeClear.lowerBound < completionClear.lowerBound)
        #expect(completionFence.lowerBound < durableFinalization.lowerBound)
        #expect(durableFinalization.lowerBound < ownershipRevalidation.lowerBound)
        #expect(ownershipRevalidation.lowerBound < queueDeletion.lowerBound)

        let failureClaim = try #require(failure.range(
            of: "guard let generation = claimInferenceGeneration("
        ))
        let probeCancellation = try #require(failure.range(
            of: "cancelInferenceStatusProbe("
        ))
        let cancelledTransport = try #require(failure.range(
            of: "nsError.code == NSURLErrorCancelled"
        ))
        let retry = try #require(failure.range(
            of: "await handleInferenceRetry("
        ))

        #expect(failureClaim.lowerBound < probeCancellation.lowerBound)
        #expect(probeCancellation.lowerBound < cancelledTransport.lowerBound)
        #expect(cancelledTransport.lowerBound < retry.lowerBound)
    }

    @Test func crossFileLifecycleAndRecoverySeamsHaveExactConsumers() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)

        for (token, expectedConsumers) in Self.expectedConsumersByToken {
            #expect(
                try consumers(of: token, in: sources, below: root)
                    == expectedConsumers,
                "Unexpected consumer for \(token)"
            )
        }
    }

    @Test func retryableServerFailureRevalidatesAfterPersistence() throws {
        let root = try offlineSyncRoot()
        let recovery = try source(Self.recoveryPath, below: root)
        let start = try #require(recovery.range(
            of: "private func scheduleRetryableServerFailure("
        ))
        let end = try #require(recovery.range(
            of: "func recoverCompletedInferenceFromServer("
        ))
        let scheduling = String(recovery[start.lowerBound..<end.lowerBound])
        let persistence = try #require(scheduling.range(
            of: "guard let retries = await retryActor.scheduleInferenceRetry("
        ))
        let durableWake = try #require(scheduling.range(
            of: "OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)"
        ))
        let revalidation = try #require(scheduling.range(
            of: "guard !Task.isCancelled,"
        ))
        let pollOwnership = try #require(scheduling.range(
            of: "isServerIngestionPollCurrent(scanId: scanId, token: serverPollToken)"
        ))
        let processWake = try #require(scheduling.range(
            of: "serverIngestionPollTasks.replace("
        ))
        let persistenceToWake = scheduling[
            persistence.lowerBound..<durableWake.lowerBound
        ]

        #expect(persistence.lowerBound < durableWake.lowerBound)
        #expect(
            persistenceToWake.components(separatedBy: "await ").count == 2
        )
        #expect(durableWake.lowerBound < revalidation.lowerBound)
        #expect(revalidation.lowerBound < pollOwnership.lowerBound)
        #expect(pollOwnership.lowerBound < processWake.lowerBound)
    }

    @Test func generalRetryRestoresDurableWakeBeforePostPersistenceFence() throws {
        let root = try offlineSyncRoot()
        let retry = try source(Self.retryPath, below: root)
        let start = try #require(retry.range(
            of: "func handleInferenceRetry("
        ))
        let scheduling = String(retry[start.lowerBound...])
        let persistence = try #require(scheduling.range(
            of: "guard let retries = await retryActor.scheduleInferenceRetry("
        ))
        let committed = String(scheduling[persistence.lowerBound...])
        let durableWake = try #require(committed.range(
            of: "OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)"
        ))
        let revalidation = try #require(committed.range(
            of: "guard !Task.isCancelled,"
        ))
        let processWake = try #require(committed.range(
            of: "inferenceRetryTasks.replace("
        ))
        let persistenceToWake = committed[..<durableWake.lowerBound]

        #expect(
            persistenceToWake.components(separatedBy: "await ").count == 2
        )
        #expect(durableWake.lowerBound < revalidation.lowerBound)
        #expect(revalidation.lowerBound < processWake.lowerBound)
    }

    @Test func focusedBehavioralTestsMirrorTheNewOwners() throws {
        let repository = try repositoryRoot()
        let lifecycleTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferenceLifecycleTests.swift"
        ))
        let dispatchTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferenceDispatchTests.swift"
        ))
        let completionTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferenceCompletionTests.swift"
        ))
        let watchdogTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferenceWatchdogTests.swift"
        ))
        let recoveryTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferenceRecoveryTests.swift"
        ))
        let retryTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferenceRetryTests.swift"
        ))
        let policyTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundInferencePolicyTests.swift"
        ))
        let legacyAggregate = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift"
        ))
        let transferTests = try contents(of: repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundTransferOwnershipTests.swift"
        ))

        #expect(lifecycleTests.contains(
            "struct BackgroundInferenceLifecycleTests"
        ))
        #expect(lifecycleTests.contains(
            ".sharedProcessState(.offlineQueueManager)"
        ))
        #expect(dispatchTests.contains(
            "struct BackgroundInferenceDispatchTests"
        ))
        #expect(completionTests.contains(
            "struct BackgroundInferenceCompletionTests"
        ))
        #expect(completionTests.contains(
            ".sharedProcessState(.offlineQueueManager)"
        ))
        #expect(watchdogTests.contains(
            "struct BackgroundInferenceWatchdogTests"
        ))
        #expect(watchdogTests.contains(
            ".sharedProcessState(.offlineQueueManager)"
        ))
        #expect(recoveryTests.contains(
            "struct BackgroundInferenceRecoveryTests"
        ))
        #expect(recoveryTests.contains(
            ".sharedProcessState(.offlineQueueManager)"
        ))
        #expect(retryTests.contains(
            "struct BackgroundInferenceRetryTests"
        ))
        #expect(retryTests.contains(
            ".sharedProcessState(.offlineQueueManager)"
        ))
        #expect(policyTests.contains(
            "struct BackgroundInferencePolicyTests"
        ))

        for declaration in Self.lifecycleTestDeclarations {
            #expect(lifecycleTests.contains(declaration))
        }
        for declaration in Self.dispatchTestDeclarations {
            #expect(dispatchTests.contains(declaration))
        }
        for declaration in Self.completionTestDeclarations {
            #expect(completionTests.contains(declaration))
        }
        for declaration in Self.watchdogTestDeclarations {
            #expect(watchdogTests.contains(declaration))
        }
        for declaration in Self.recoveryTestDeclarations {
            #expect(recoveryTests.contains(declaration))
            #expect(!legacyAggregate.contains(declaration))
        }
        for declaration in Self.retryTestDeclarations {
            #expect(retryTests.contains(declaration))
            #expect(!legacyAggregate.contains(declaration))
        }
        for declaration in Self.policyTestDeclarations {
            #expect(policyTests.contains(declaration))
            #expect(!legacyAggregate.contains(declaration))
        }
        #expect(!transferTests.contains(
            "func rejectedInferenceDispatchRetiresOwnershipBeforeCancellation("
        ))
    }

    private static let policyPath =
        "Policies/BackgroundInferencePolicy.swift"
    private static let lifecyclePath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceLifecycle.swift"
    private static let dispatchPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift"
    private static let completionPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift"
    private static let finalizationPath =
        "Services/BackgroundInference/BackgroundInferenceFinalizationService.swift"
    private static let watchdogPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift"
    private static let recoveryPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift"
    private static let reconciliationPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceReconciliation.swift"
    private static let retryPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift"
    private static let retiredAggregatePath =
        "OfflineQueueManager+URLSession.swift"
    private static let durabilityPath =
        "OfflineQueueDurability.swift"
    private static let accountWorkPath =
        "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"
    private static let terminalRoutingPath =
        "Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift"

    private static let expectedImportsByPath: [String: Set<String>] = [
        policyPath: ["import Foundation"],
        lifecyclePath: ["import Foundation"],
        dispatchPath: ["import Foundation"],
        completionPath: ["import Foundation"],
        finalizationPath: ["import Foundation"],
        watchdogPath: ["import Foundation"],
        recoveryPath: ["import Foundation", "import SwiftData"],
        reconciliationPath: ["import Foundation"],
        retryPath: ["import Foundation"]
    ]

    private static let declarationOwners: [String: String] = [
        "enum ScanStatusRecoveryAction": policyPath,
        "enum BackgroundInferenceResponseDisposition": policyPath,
        "enum BackgroundInferencePolicy": policyPath,
        "func shouldRetryBackgroundInferenceRouteFailure": policyPath,
        "func backgroundInferenceResponseDisposition": policyPath,
        "func requiresMediaRestagingAfterServerFailure": policyPath,
        "func scanStatusRecoveryAction": policyPath,
        "func scanStatusActionPermitsInferenceDispatch": policyPath,
        "func parseRetryAfterDate": policyPath,
        "func claimInferenceGeneration": lifecyclePath,
        "func isInferenceGenerationCurrent": lifecyclePath,
        "func finishInferenceGeneration": lifecyclePath,
        "enum BackgroundInferencePreparationRace": dispatchPath,
        "func firstValue": dispatchPath,
        "func dispatchInferenceDownloadTask": dispatchPath,
        "func prepareInferenceDownloadRequestWithTimeout": dispatchPath,
        "func buildInferenceDownloadRequest": dispatchPath,
        "func processInferenceDownloadResult": completionPath,
        "func handleInferenceTaskNetworkFailure": completionPath,
        "func cancelInferenceStatusProbe": completionPath,
        "struct BackgroundInferenceFinalizationService": finalizationPath,
        "func processAndCleanupOfflineScan": finalizationPath,
        "func processAssumingPersistenceLock": finalizationPath,
        "func scheduleInferenceStatusProbe": watchdogPath,
        "func isLiveInferenceTask": watchdogPath,
        "func cancelActiveInferenceTasks": watchdogPath,
        "func activeInferenceTaskCount": watchdogPath,
        "enum CompletedServerResultHydrationOutcome": recoveryPath,
        "func clearServerIngestionState": recoveryPath,
        "func scheduleRetryableServerFailure": recoveryPath,
        "func recoverCompletedInferenceFromServer": recoveryPath,
        "func recoverFoundScanFromServer": recoveryPath,
        "func deferCompletedServerResultRecovery": recoveryPath,
        "func serverOwnedInferencingScanIds": reconciliationPath,
        "func promoteRecoveredLocalScan": recoveryPath,
        "func isServerIngestionPollCurrent": retryPath,
        "func scheduleServerIngestionPoll": retryPath,
        "func handleInferenceRetry": retryPath
    ]

    private static let expectedConsumersByToken: [String: Set<String>] = [
        "claimInferenceGeneration(": [
            completionPath,
            dispatchPath,
            lifecyclePath
        ],
        "isInferenceGenerationCurrent(": [
            completionPath,
            dispatchPath,
            lifecyclePath,
            recoveryPath,
            retryPath
        ],
        "finishInferenceGeneration(": [
            completionPath,
            dispatchPath,
            lifecyclePath,
            watchdogPath,
            accountWorkPath,
            terminalRoutingPath
        ],
        "scheduleInferenceStatusProbe(": [
            dispatchPath,
            watchdogPath
        ],
        "recoverCompletedInferenceFromServer(": [
            dispatchPath,
            reconciliationPath,
            recoveryPath,
            retryPath,
            watchdogPath
        ],
        "isServerIngestionPollCurrent(": [
            recoveryPath,
            retryPath
        ],
        "scheduleServerIngestionPoll(": [
            recoveryPath,
            retryPath
        ],
        "handleInferenceRetry(": [
            completionPath,
            dispatchPath,
            retryPath,
            watchdogPath,
            "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift"
        ],
        "isLiveInferenceTask(": [
            dispatchPath,
            watchdogPath
        ],
        "cancelActiveInferenceTasks(": [watchdogPath],
        "activeInferenceTaskCount(": [watchdogPath],
        "processInferenceDownloadResult(": [
            completionPath,
            terminalRoutingPath
        ],
        "handleInferenceTaskNetworkFailure(": [
            completionPath,
            terminalRoutingPath
        ],
        "cancelInferenceStatusProbe(": [
            completionPath
        ],
        "processAndCleanupOfflineScan(": [
            completionPath,
            finalizationPath
        ],
        "inferenceCompletionGenerations": [
            completionPath,
            "OfflineQueueManager.swift",
            "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift"
        ],
        "inferenceStatusProbeTasks": [
            completionPath,
            lifecyclePath,
            watchdogPath,
            "OfflineQueueManager.swift",
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift"
        ],
        "BackgroundInferencePolicy.requiredConsentAttentionMessage": [
            completionPath,
            dispatchPath
        ],
        "BackgroundInferencePolicy.backgroundInferenceResponseDisposition(": [
            completionPath
        ],
        "BackgroundInferencePolicy.scanStatusRecoveryAction(": [
            recoveryPath
        ],
        "BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(": [
            recoveryPath
        ],
        "BackgroundInferencePolicy.scanStatusActionPermitsInferenceDispatch(": [
            dispatchPath
        ],
        "BackgroundInferencePolicy.parseRetryAfterDate": [
            durabilityPath
        ],
        "activeInferenceGenerations": [
            completionPath,
            "OfflineQueueManager.swift",
            lifecyclePath,
            recoveryPath,
            retryPath,
            watchdogPath,
            "Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift",
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift"
        ]
    ]

    private static let lifecycleTestDeclarations = [
        "func generationClaimIsExactAndIdempotent(",
        "func retiredGenerationCannotBeReadopted(",
        "func nilLegacyGenerationClaimsANewExactOwner(",
        "func staleCompletionCannotClearReplacementGeneration("
    ]

    private static let dispatchTestDeclarations = [
        "func preparationCanFinishBeforeTimeout(",
        "func timeoutWinsDeterministicallyAndCancelsPreparation(",
        "func callerCancellationCancelsPreparationRace(",
        "func timeoutDoesNotAwaitNonCooperativePreparation(",
        "func dispatchRevalidatesPreparationAcrossSuspensions(",
        "func rejectedDispatchRetiresOwnershipBeforeCancellation(",
        "func failedRetirementPreservesDurableGenerationOwnership("
    ]

    private static let completionTestDeclarations = [
        "func cancelledTaskRetiresExactGenerationAndProbe(",
        "func staleNetworkFailureCannotClearReplacementGeneration(",
        "func staleResultCleansFileWithoutTouchingReplacement("
    ]

    private static let watchdogTestDeclarations = [
        "func probeReplacementPreservesExactGenerationOwnership(",
        "func liveTaskMatchingUsesParsedScanIdentityAndOpenState(",
        "func watchdogRevalidatesBeforeRetirementAndRetry("
    ]

    private static let recoveryTestDeclarations = [
        "func testFoundServerStatusPersistsOwnershipBeforeLocalHydration(",
        "func testCompletedServerResultContractMismatchPausesWithoutRetryLoop("
    ]

    private static let retryTestDeclarations = [
        "func scheduledServerFailureMarkerIsReadFromDurableStore(",
        "func persistedRetryWakeSurvivesCancelledProcessOwner(",
        "func pollTokenValidationRejectsReplacementOwner("
    ]

    private static let policyTestDeclarations = [
        "func scheduledServerFailureRetryBreaksStatusUploadDeadlock(",
        "func backgroundInferencePlatformRoute404RemainsRetryable(",
        "func backgroundInferencePreservesRecoverableHTTPFailures(",
        "func testScanStatusRecoveryActionRespectsServerIngestionState("
    ]

    private func offlineSyncRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Data/OfflineSync"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func source(_ path: String, below root: URL) throws -> String {
        try contents(of: root.appendingPathComponent(path))
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func imports(in source: String) -> Set<String> {
        Set(
            source.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
        )
    }

    private func lineCount(of source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func relativePath(of file: URL, below root: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    private func consumers(
        of token: String,
        in sources: [URL],
        below root: URL
    ) throws -> Set<String> {
        try Set(sources.compactMap { file -> String? in
            guard try contents(of: file).contains(token) else { return nil }
            return relativePath(of: file, below: root)
        })
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }
        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return file
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: declaration)
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|final|static|nonisolated)\s+)*"#
            + escaped
            + #"(?:\s*[:(<{=])"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }
}
