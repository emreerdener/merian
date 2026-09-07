import Foundation
import Testing

@Suite("Offline Queue Background Transfer Architecture")
struct BackgroundTransferArchitectureTests {
    @Test func focusedFilesAndDeclarationsHaveExactOwners() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)
        let transferRoot = root.appendingPathComponent(
            "Services/BackgroundTransfer"
        )
        let transferPaths = try swiftFiles(below: transferRoot).map {
            relativePath(of: $0, below: root)
        }

        #expect(Set(transferPaths) == Set(Self.expectedImportsByPath.keys))

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
            let source = try contents(
                of: root.appendingPathComponent(path)
            )
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

    @Test func mutableStateAndPrivateValidationRemainContained() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)
        let tracker = try source(Self.trackerPath, below: root)
        let accountWork = try source(Self.accountWorkPath, below: root)
        let delegate = try source(Self.delegatePath, below: root)
        let terminalRouting = try source(
            Self.terminalRoutingPath,
            below: root
        )
        let backgroundInferencePipeline = try [
            source(Self.inferenceRecoveryPath, below: root),
            source(Self.inferenceRetryPath, below: root)
        ].joined(separator: "\n")
        let manager = try source("OfflineQueueManager.swift", below: root)

        #expect(tracker.contains("private let lock = NSLock()"))
        #expect(tracker.contains("private var activeTokens:"))
        #expect(tracker.contains("private var idleWaiters:"))
        #expect(!tracker.contains("activeCountForTesting"))
        #expect(!tracker.contains("OfflineQueueManager.shared"))
        #expect(!tracker.contains("SupabaseManager"))

        #expect(accountWork.contains(
            "private let backgroundAccountWorkQuiescenceTimeout:"
        ))
        #expect(accountWork.contains("SupabaseManager.shared"))
        #expect(accountWork.contains("backgroundSession.allTasks"))
        #expect(accountWork.contains(".retireBackgroundAccountWork("))
        #expect(accountWork.contains(
            "func retireRejectedBackgroundAccountWork("
        ))
        #expect(!accountWork.contains("BackgroundTaskWrapper"))
        #expect(!accountWork.contains("FileManager.default"))
        #expect(!accountWork.contains(
            "validateOrAdoptBackgroundAccountWork("
        ))

        #expect(delegate.contains(
            "extension OfflineQueueManager: URLSessionTaskDelegate, URLSessionDownloadDelegate"
        ))
        #expect(delegate.components(
            separatedBy: "nonisolated func urlSession("
        ).count == 3)
        #expect(delegate.contains("backgroundTerminalWorkTracker.begin()"))
        #expect(delegate.contains("BackgroundTaskWrapper.execute"))
        #expect(!delegate.contains("import SwiftData"))
        #expect(!delegate.contains("SupabaseManager"))
        #expect(!delegate.contains("backgroundAccountWorkLeases"))

        #expect(terminalRouting.contains(
            "private func backgroundTaskOwnerLeaseIsCurrentOrAdopted("
        ))
        #expect(terminalRouting.contains(
            "private func validateOrAdoptBackgroundAccountWork("
        ))
        #expect(terminalRouting.contains("func processUploadTerminalCallback("))
        #expect(terminalRouting.contains(
            "func processInferenceTerminalResult("
        ))
        #expect(terminalRouting.contains(
            "func processInferenceTerminalFailure("
        ))
        #expect(!terminalRouting.contains("import SwiftData"))
        #expect(!terminalRouting.contains("URLSessionTaskDelegate"))

        #expect(!backgroundInferencePipeline.contains(
            "URLSessionTaskDelegate"
        ))
        #expect(!backgroundInferencePipeline.contains(
            "func quiesceBackgroundAccountWorkForAuthTransition("
        ))
        #expect(!backgroundInferencePipeline.contains(
            "private func backgroundTaskOwnerLeaseIsCurrentOrAdopted("
        ))
        #expect(!backgroundInferencePipeline.contains(
            "private func validateOrAdoptBackgroundAccountWork("
        ))
        #expect(!backgroundInferencePipeline.contains(
            "func processUploadTerminalCallback("
        ))
        #expect(!backgroundInferencePipeline.contains(
            "func processInferenceTerminalResult("
        ))
        #expect(!backgroundInferencePipeline.contains(
            "func processInferenceTerminalFailure("
        ))

        #expect(manager.contains(
            "nonisolated static let backgroundTerminalWorkTracker"
        ))
        #expect(manager.contains(
            "@ObservationIgnored var backgroundAccountWorkLeases:"
        ))
        #expect(!manager.contains(
            "final class BackgroundURLSessionTerminalWorkTracker"
        ))
        #expect(!manager.contains(
            "func invokeBackgroundSessionCompletionAfterTerminalWork("
        ))

        let leaseStateConsumers = try consumers(
            of: "backgroundAccountWorkLeases",
            in: sources,
            below: root
        )
        #expect(leaseStateConsumers == Self.expectedLeaseStateConsumers)

        let rejectedRetirementConsumers = try consumers(
            of: "retireRejectedBackgroundAccountWork(",
            in: sources,
            below: root
        )
        #expect(
            rejectedRetirementConsumers ==
                Self.expectedRejectedRetirementConsumers
        )

        let inferenceCompletionConsumers = try consumers(
            of: "finishInferenceGeneration(",
            in: sources,
            below: root
        )
        #expect(
            inferenceCompletionConsumers == Self.expectedInferenceCompletionConsumers
        )

        let trackerConsumers = try consumers(
            of: "backgroundTerminalWorkTracker",
            in: sources,
            below: root
        )
        #expect(trackerConsumers == Self.expectedTrackerConsumers)
    }

    @Test func terminalRegistrationAndQuiescenceOrderingRemainExplicit() throws {
        let root = try offlineSyncRoot()
        let delegate = try source(Self.delegatePath, below: root)
        let accountWork = try source(Self.accountWorkPath, below: root)
        let tracker = try source(Self.trackerPath, below: root)
        let terminalRouting = try source(
            Self.terminalRoutingPath,
            below: root
        )

        let downloadStart = try #require(delegate.range(
            of: "didFinishDownloadingTo location: URL"
        ))
        let taskCompletionStart = try #require(delegate.range(
            of: "didCompleteWithError error: Error?",
            range: downloadStart.upperBound..<delegate.endIndex
        ))
        let sessionCompletionStart = try #require(delegate.range(
            of: "urlSessionDidFinishEvents(forBackgroundURLSession",
            range: taskCompletionStart.upperBound..<delegate.endIndex
        ))
        let downloadBody = delegate[
            downloadStart.lowerBound..<taskCompletionStart.lowerBound
        ]
        let firstDownloadRegistration = try #require(downloadBody.range(
            of: ".backgroundTerminalWorkTracker.begin()"
        ))
        let firstDownloadHandoff = try #require(downloadBody.range(
            of: "BackgroundTaskWrapper.execute",
            range: firstDownloadRegistration.upperBound..<downloadBody.endIndex
        ))
        let secondDownloadRegistration = try #require(downloadBody.range(
            of: ".backgroundTerminalWorkTracker.begin()",
            range: firstDownloadHandoff.upperBound..<downloadBody.endIndex
        ))
        let secondDownloadHandoff = try #require(downloadBody.range(
            of: "BackgroundTaskWrapper.execute",
            range: secondDownloadRegistration.upperBound..<downloadBody.endIndex
        ))
        #expect(
            firstDownloadRegistration.lowerBound <
                firstDownloadHandoff.lowerBound
        )
        #expect(
            secondDownloadRegistration.lowerBound <
                secondDownloadHandoff.lowerBound
        )

        let taskCompletionBody = delegate[
            taskCompletionStart.lowerBound..<sessionCompletionStart.lowerBound
        ]
        let taskRegistration = try #require(taskCompletionBody.range(
            of: ".backgroundTerminalWorkTracker.begin()"
        ))
        let taskHandoff = try #require(taskCompletionBody.range(
            of: "BackgroundTaskWrapper.execute"
        ))
        #expect(taskRegistration.lowerBound < taskHandoff.lowerBound)

        let normalizedAccountWork = normalizedSource(accountWork)
        let durableSweep = try #require(normalizedAccountWork.range(
            of: ".backgroundAccountWorkCandidates(ownerUserID: sourceUserID)"
        ))
        let transportSnapshot = try #require(normalizedAccountWork.range(
            of: "let tasks = await backgroundSession.allTasks",
            range: durableSweep.upperBound..<normalizedAccountWork.endIndex
        ))
        let retirement = try #require(normalizedAccountWork.range(
            of: ".retireBackgroundAccountWork(",
            range: transportSnapshot.upperBound..<normalizedAccountWork.endIndex
        ))
        let inferenceCompletion = try #require(normalizedAccountWork.range(
            of: "finishInferenceGeneration(",
            range: retirement.upperBound..<normalizedAccountWork.endIndex
        ))
        let retirementFence = try #require(normalizedAccountWork.range(
            of: "guard !retirementFailed else { return false }",
            range:
            inferenceCompletion.upperBound..<normalizedAccountWork.endIndex
        ))
        let cancellation = try #require(normalizedAccountWork.range(
            of: "task.cancel()",
            range: retirementFence.upperBound..<normalizedAccountWork.endIndex
        ))
        #expect(durableSweep.lowerBound < transportSnapshot.lowerBound)
        #expect(transportSnapshot.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < inferenceCompletion.lowerBound)
        #expect(inferenceCompletion.lowerBound < retirementFence.lowerBound)
        #expect(retirementFence.lowerBound < cancellation.lowerBound)

        let normalizedTracker = normalizedSource(tracker)
        let idleWait = try #require(normalizedTracker.range(
            of: "await tracker.waitUntilIdle()"
        ))
        let completion = try #require(normalizedTracker.range(
            of: "takeHandler()?()",
            range: idleWait.upperBound..<normalizedTracker.endIndex
        ))
        #expect(idleWait.lowerBound < completion.lowerBound)

        let normalizedTerminalRouting = normalizedSource(terminalRouting)
        let ownerCheck = try #require(normalizedTerminalRouting.range(
            of: "private func backgroundTaskOwnerLeaseIsCurrentOrAdopted("
        ))
        let validation = try #require(normalizedTerminalRouting.range(
            of: "private func validateOrAdoptBackgroundAccountWork(",
            range: ownerCheck.upperBound..<normalizedTerminalRouting.endIndex
        ))
        let ownerCheckBody = normalizedTerminalRouting[
            ownerCheck.lowerBound..<validation.lowerBound
        ]
        let relaunchedLease = try #require(ownerCheckBody.range(
            of: ".beginUnownedAccountBoundWork(expectedUserID: ownerUserID)"
        ))
        let retainedLease = try #require(ownerCheckBody.range(
            of: "retainBackgroundAccountWork(",
            range: relaunchedLease.upperBound..<ownerCheckBody.endIndex
        ))
        #expect(relaunchedLease.lowerBound < retainedLease.lowerBound)

        let uploadTerminal = try #require(normalizedTerminalRouting.range(
            of: "func processUploadTerminalCallback(",
            range: validation.upperBound..<normalizedTerminalRouting.endIndex
        ))
        let validationBody = normalizedTerminalRouting[
            validation.lowerBound..<uploadTerminal.lowerBound
        ]
        let leaseGate = try #require(validationBody.range(
            of: "backgroundTaskOwnerLeaseIsCurrentOrAdopted("
        ))
        let durableCheck = try #require(validationBody.range(
            of: ".backgroundAccountWorkIsCurrent(",
            range: leaseGate.upperBound..<validationBody.endIndex
        ))
        let durableAdoption = try #require(validationBody.range(
            of: ".activateBackgroundAccountWork(",
            range: durableCheck.upperBound..<validationBody.endIndex
        ))
        #expect(leaseGate.lowerBound < durableCheck.lowerBound)
        #expect(durableCheck.lowerBound < durableAdoption.lowerBound)

        #expect(normalizedTerminalRouting.components(
            separatedBy:
            "defer { finishBackgroundAccountWork(for: taskIdentifier) }"
        ).count == 4)

        let rejectedRetirement = try #require(
            normalizedTerminalRouting.range(
                of: "await Self.awaitDurableBackgroundWorkRetirement(",
                range:
                uploadTerminal.upperBound..<normalizedTerminalRouting.endIndex
            )
        )
        let uploadInvalidation = try #require(
            normalizedTerminalRouting.range(
                of: "invalidateUploadGeneration(",
                range:
                rejectedRetirement.upperBound..<normalizedTerminalRouting.endIndex
            )
        )
        #expect(rejectedRetirement.lowerBound < uploadInvalidation.lowerBound)

        #expect(normalizedTerminalRouting.components(
            separatedBy: "finishInferenceGeneration("
        ).count == 3)
        let inferenceTerminal = try #require(
            normalizedTerminalRouting.range(
                of: "func processInferenceTerminalResult(",
                range:
                uploadTerminal.upperBound..<normalizedTerminalRouting.endIndex
            )
        )
        let inferenceRetirement = try #require(
            normalizedTerminalRouting.range(
                of: "await Self.awaitDurableBackgroundWorkRetirement(",
                range:
                inferenceTerminal.upperBound..<normalizedTerminalRouting.endIndex
            )
        )
        let retiredGenerationCompletion = try #require(
            normalizedTerminalRouting.range(
                of: "finishInferenceGeneration(",
                range:
                inferenceRetirement.upperBound..<normalizedTerminalRouting.endIndex
            )
        )
        #expect(inferenceRetirement.lowerBound < retiredGenerationCompletion.lowerBound)
    }

    @Test func focusedBehavioralTestsMirrorTheNewOwners() throws {
        let repository = try repositoryRoot()
        let testSource = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundTransferOwnershipTests.swift"
            )
        )
        let legacyAggregate = try contents(
            of: repository.appendingPathComponent(
                "apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift"
            )
        )

        #expect(testSource.contains(
            "struct BackgroundTransferOwnershipTests"
        ))
        #expect(testSource.contains("\"Background Transfer Ownership\""))
        #expect(testSource.contains(".serialized"))
        #expect(testSource.contains(
            ".sharedProcessState(.offlineQueueManager)"
        ))
        #expect(
            lineCount(of: testSource) <= 600,
            "BackgroundTransferOwnershipTests.swift exceeds the 600-line review ceiling"
        )

        for declaration in Self.expectedTestDeclarations {
            #expect(testSource.contains(declaration))
            #expect(!legacyAggregate.contains(declaration))
        }
    }

    private static let trackerPath =
        "Services/BackgroundTransfer/BackgroundURLSessionTerminalWorkTracker.swift"
    private static let accountWorkPath =
        "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"
    private static let delegatePath =
        "Services/BackgroundTransfer/OfflineQueueManager+URLSessionDelegate.swift"
    private static let terminalRoutingPath =
        "Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift"
    private static let inferenceDispatchPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift"
    private static let inferenceLifecyclePath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceLifecycle.swift"
    private static let inferenceCompletionPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceCompletion.swift"
    private static let inferenceRecoveryPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift"
    private static let inferenceRetryPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift"
    private static let inferenceWatchdogPath =
        "Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift"

    private static let expectedImportsByPath: [String: Set<String>] = [
        trackerPath: ["import Foundation"],
        accountWorkPath: ["import Foundation", "import SwiftData"],
        delegatePath: ["import Foundation"],
        terminalRoutingPath: ["import Foundation"]
    ]

    private static let declarationOwners: [String: String] = [
        "class BackgroundURLSessionTerminalWorkTracker": trackerPath,
        "func invokeBackgroundSessionCompletionAfterTerminalWork": trackerPath,
        "func awaitDurableBackgroundWorkRetirement": accountWorkPath,
        "func waitForDurableBackgroundWorkRetirementRetry": accountWorkPath,
        "func retireRejectedBackgroundAccountWork": accountWorkPath,
        "func retainBackgroundAccountWork": accountWorkPath,
        "func finishBackgroundAccountWork": accountWorkPath,
        "func quiesceBackgroundAccountWorkForAuthTransition": accountWorkPath,
        "func backgroundTaskOwnerLeaseIsCurrentOrAdopted": terminalRoutingPath,
        "func validateOrAdoptBackgroundAccountWork": terminalRoutingPath,
        "func processUploadTerminalCallback": terminalRoutingPath,
        "func processInferenceTerminalResult": terminalRoutingPath,
        "func processInferenceTerminalFailure": terminalRoutingPath,
        "func finishInferenceGeneration": inferenceLifecyclePath
    ]

    private static let expectedLeaseStateConsumers: Set<String> = [
        "OfflineQueueManager.swift",
        accountWorkPath,
        terminalRoutingPath
    ]

    private static let expectedRejectedRetirementConsumers: Set<String> = [
        inferenceDispatchPath,
        accountWorkPath,
        terminalRoutingPath
    ]

    private static let expectedInferenceCompletionConsumers: Set<String> = [
        inferenceCompletionPath,
        inferenceDispatchPath,
        inferenceLifecyclePath,
        inferenceWatchdogPath,
        accountWorkPath,
        terminalRoutingPath
    ]

    private static let expectedTrackerConsumers: Set<String> = [
        "OfflineQueueManager.swift",
        delegatePath
    ]

    private static let expectedTestDeclarations = [
        "func backgroundSessionCompletionWaitsForTerminalPersistence(",
        "func backgroundSessionCompletionReturnsImmediatelyWhenIdle(",
        "func backgroundURLSessionTerminalOwnershipIsRegisteredSynchronously(",
        "func authTransitionQuiescenceSweepsDurableOwnersWithoutTransportTasks(",
        "func relaunchedTerminalCallbackReacquiresLeaseBeforeActorValidation(",
        "func failedDurableRetirementCannotReachTransportCancellation(",
        "func persistentRetirementFailureCannotAuthorizeCancellation("
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

    private func normalizedSource(_ source: String) -> String {
        source.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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
