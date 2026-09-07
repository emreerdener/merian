import Foundation
@testable import Merian
import Testing

@Suite(
    "Background Transfer Ownership",
    .serialized,
    .sharedProcessState(.offlineQueueManager)
)
@MainActor
struct BackgroundTransferOwnershipTests {
    @Test func backgroundSessionCompletionWaitsForTerminalPersistence() async {
        let tracker = BackgroundURLSessionTerminalWorkTracker()
        let firstToken = tracker.begin()
        let secondToken = tracker.begin()
        var completionCount = 0
        var completionHandler: (() -> Void)? = {
            completionCount += 1
        }
        let firstWaiter = Task { @MainActor in
            await OfflineQueueManager
                .invokeBackgroundSessionCompletionAfterTerminalWork(
                    tracker: tracker,
                    takeHandler: {
                        let handler = completionHandler
                        completionHandler = nil
                        return handler
                    }
                )
            return true
        }
        let secondWaiter = Task { @MainActor in
            await OfflineQueueManager
                .invokeBackgroundSessionCompletionAfterTerminalWork(
                    tracker: tracker,
                    takeHandler: {
                        let handler = completionHandler
                        completionHandler = nil
                        return handler
                    }
                )
            return true
        }

        await Task.yield()
        #expect(completionCount == 0)
        tracker.finish(firstToken)
        await Task.yield()
        #expect(completionCount == 0)
        tracker.finish(secondToken)
        #expect(await firstWaiter.value)
        #expect(await secondWaiter.value)
        #expect(completionCount == 1)

        // Duplicate terminal callbacks cannot underflow the tracker or resume
        // a later waiter twice.
        tracker.finish(firstToken)
        tracker.finish(secondToken)
        await OfflineQueueManager
            .invokeBackgroundSessionCompletionAfterTerminalWork(
                tracker: tracker,
                takeHandler: {
                    let handler = completionHandler
                    completionHandler = nil
                    return handler
                }
            )
        #expect(completionCount == 1)
    }

    @Test func backgroundSessionCompletionReturnsImmediatelyWhenIdle() async {
        let tracker = BackgroundURLSessionTerminalWorkTracker()
        var completionCount = 0

        await OfflineQueueManager
            .invokeBackgroundSessionCompletionAfterTerminalWork(
                tracker: tracker,
                takeHandler: {
                    { completionCount += 1 }
                }
            )

        #expect(completionCount == 1)
    }

    @Test func backgroundURLSessionTerminalOwnershipIsRegisteredSynchronously() throws {
        let source = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+URLSessionDelegate.swift"
        )
        let downloadStart = try #require(source.range(
            of: "didFinishDownloadingTo location: URL"
        ))
        let taskCompletionStart = try #require(source.range(
            of: "didCompleteWithError error: Error?",
            range: downloadStart.upperBound..<source.endIndex
        ))
        let sessionCompletionStart = try #require(source.range(
            of: "urlSessionDidFinishEvents(forBackgroundURLSession",
            range: taskCompletionStart.upperBound..<source.endIndex
        ))
        let downloadBody = source[downloadStart.lowerBound..<taskCompletionStart.lowerBound]
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

        let taskCompletionBody =
            source[taskCompletionStart.lowerBound..<sessionCompletionStart.lowerBound]
        let taskRegistration = try #require(taskCompletionBody.range(
            of: ".backgroundTerminalWorkTracker.begin()"
        ))
        let taskHandoff = try #require(taskCompletionBody.range(
            of: "BackgroundTaskWrapper.execute"
        ))
        #expect(taskRegistration.lowerBound < taskHandoff.lowerBound)

        let finalCallback = source[sessionCompletionStart.lowerBound...]
        #expect(finalCallback.contains(
            "invokeBackgroundSessionCompletionAfterTerminalWork"
        ))
    }

    @Test func authTransitionQuiescenceSweepsDurableOwnersWithoutTransportTasks() throws {
        let source = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"
        )
        let quiescenceStart = try #require(source.range(
            of: "func quiesceBackgroundAccountWorkForAuthTransition("
        ))
        let body = source[quiescenceStart.lowerBound...]

        let durableSweep = try #require(body.range(
            of: ".backgroundAccountWorkCandidates(ownerUserID: sourceUserID)"
        ))
        let transportSnapshot = try #require(body.range(
            of: "let tasks = await backgroundSession.allTasks"
        ))
        let retirement = try #require(body.range(
            of: ".retireBackgroundAccountWork(",
            range: durableSweep.upperBound..<body.endIndex
        ))
        let cancellation = try #require(body.range(
            of: "task.cancel()",
            range: retirement.upperBound..<body.endIndex
        ))

        #expect(durableSweep.lowerBound < transportSnapshot.lowerBound)
        #expect(transportSnapshot.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < cancellation.lowerBound)
    }

    @Test func relaunchedTerminalCallbackReacquiresLeaseBeforeActorValidation() throws {
        let terminalValidationSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundTerminalRouting.swift"
        )
        let accountWorkSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"
        )
        let ownerCheckStart = try #require(terminalValidationSource.range(
            of: "private func backgroundTaskOwnerLeaseIsCurrentOrAdopted("
        ))
        let validationStart = try #require(terminalValidationSource.range(
            of: "private func validateOrAdoptBackgroundAccountWork(",
            range: ownerCheckStart.upperBound..<terminalValidationSource.endIndex
        ))
        let ownerCheckBody =
            terminalValidationSource[
                ownerCheckStart.lowerBound..<validationStart.lowerBound
            ]
        let leaseAdmission = try #require(ownerCheckBody.range(
            of: ".beginUnownedAccountBoundWork(expectedUserID: ownerUserID)"
        ))
        let leaseRetention = try #require(ownerCheckBody.range(
            of: "retainBackgroundAccountWork(",
            range: leaseAdmission.upperBound..<ownerCheckBody.endIndex
        ))
        #expect(leaseAdmission.lowerBound < leaseRetention.lowerBound)

        let quiescerStart = try #require(accountWorkSource.range(
            of: "func quiesceBackgroundAccountWorkForAuthTransition("
        ))
        let quiescerBody = accountWorkSource[quiescerStart.lowerBound...]
        #expect(quiescerBody.contains("backgroundAccountWorkLeases.isEmpty"))
    }

    @Test func failedDurableRetirementCannotReachTransportCancellation() async {
        var retirementResults = [false, true]
        var events: [String] = []

        let didRetire = await OfflineQueueManager
            .awaitDurableBackgroundWorkRetirement(
                retire: {
                    let result = retirementResults.removeFirst()
                    events.append(result ? "retired" : "retirement-failed")
                    return result
                },
                waitBeforeRetry: {
                    events.append("wait")
                    return true
                }
            )
        if didRetire {
            events.append("cancel")
        }

        #expect(didRetire)
        #expect(
            events == [
                "retirement-failed",
                "wait",
                "retired",
                "cancel"
            ]
        )
    }

    @Test func persistentRetirementFailureCannotAuthorizeCancellation() async {
        var retirementAttempts = 0
        var waitCount = 0

        let didRetire = await OfflineQueueManager
            .awaitDurableBackgroundWorkRetirement(
                maximumAttempts: 3,
                retire: {
                    retirementAttempts += 1
                    return false
                },
                waitBeforeRetry: {
                    waitCount += 1
                    return true
                }
            )

        #expect(!didRetire)
        #expect(retirementAttempts == 3)
        #expect(waitCount == 2)
    }
}
