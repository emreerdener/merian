import Foundation
import Testing

@testable import Merian

@MainActor
private final class InferenceLiveCompletionHarness {
    enum Event: Equatable {
        case discovery
        case replacement(String?, String)
        case circuitSuccess
        case telemetry(String?, String?)
        case foregroundCompletion(String)
        case notificationPreferenceRead
        case notification(String, String)
        case milestone(String, String)
        case queueDeleted(String, [String], UUID)
        case queueRetired(String, UUID, Bool, String)
    }

    var notificationsEnabled = true
    var queueDeleteResult = true
    var deleteOperation: (@MainActor () async -> Bool)?
    private(set) var events: [Event] = []

    func resetEvents() {
        events = []
    }

    func makeSystem() -> (
        coordinator: InferenceLiveCompletionCoordinator,
        attemptCoordinator: InferenceLiveAttemptCoordinator
    ) {
        let queueService = InferenceLiveQueueService(
            dependencies: .init(
                releaseDeferredUpload: { _, _, _ in },
                retireForegroundInference: { [self] scanId, generation, resumeBackground, reason in
                    events.append(
                        .queueRetired(
                            scanId,
                            generation,
                            resumeBackground,
                            reason
                        )
                    )
                },
                claimForegroundInferenceStart: { _, _ in true },
                isForegroundInferenceAttemptCurrent: { _, _ in true },
                foregroundInferenceGeneration: { _ in nil },
                deleteQueuedScan: { [self] scanId, mediaPaths, generation in
                    events.append(
                        .queueDeleted(scanId, mediaPaths, generation)
                    )
                    if let deleteOperation {
                        return await deleteOperation()
                    }
                    return queueDeleteResult
                },
                rejectQueuedScan: { _, _, _ in true }
            )
        )
        let attemptCoordinator = InferenceLiveAttemptCoordinator(
            queueService: queueService
        )
        let completionCoordinator = InferenceLiveCompletionCoordinator(
            attemptCoordinator: attemptCoordinator,
            dependencies: .init(
                recordNewSpeciesDiscovered: { [self] in
                    events.append(.discovery)
                },
                transferReplacementMetadataAndDeleteOriginal: { [self] scanId, outcome, _ in
                    events.append(
                        .replacement(scanId, Self.label(for: outcome))
                    )
                },
                recordCircuitSuccess: { [self] in
                    events.append(.circuitSuccess)
                },
                trackCompletedScan: { [self] tier, plan in
                    events.append(.telemetry(tier, plan))
                },
                sendEvent: { [self] event in
                    guard case let .foregroundBiologicalScanCompleted(scanId) =
                        event else { return }
                    events.append(.foregroundCompletion(scanId))
                },
                notificationsEnabled: { [self] in
                    events.append(.notificationPreferenceRead)
                    return notificationsEnabled
                },
                sendInferenceCompleteNotification: { [self] speciesName, scanId in
                    events.append(.notification(speciesName, scanId))
                },
                scheduleMilestoneProcessing: { [self] scanId, speciesData, _ in
                    events.append(
                        .milestone(scanId, speciesData.commonName)
                    )
                }
            )
        )
        return (completionCoordinator, attemptCoordinator)
    }

    private static func label(
        for outcome: InferenceLiveResultService.Outcome
    ) -> String {
        switch outcome {
        case .persisted:
            "persisted"
        case .completedWithoutRecord:
            "completed_without_record"
        case .persistenceRejected:
            "persistence_rejected"
        }
    }
}

@MainActor
@Suite("Inference Live Completion Coordinator")
struct InferenceLiveCompletionCoordinatorTests {
    @Test func persistedCompletionNormalizesAndSequencesSharedEffects() {
        let harness = InferenceLiveCompletionHarness()
        let system = harness.makeSystem()
        let completion = system.coordinator.prepare(
            outcome: .persisted(
                result(
                    isNewDiscovery: true,
                    savedImagePaths: ["saved-image.jpg"],
                    planUsed: "pro_paid"
                )
            ),
            targetEradicationScanId: "original-scan",
            modelContext: nil
        )

        #expect(completion?.speciesData.isNewDiscovery == true)
        #expect(completion?.savedImagePaths == ["saved-image.jpg"])
        #expect(
            completion?.mediaPathsToKeep == ["audio.m4a", "video.mov"]
        )
        #expect(harness.events == [
            .discovery,
            .replacement("original-scan", "persisted"),
            .circuitSuccess,
            .telemetry("pro", "pro_paid")
        ])
    }

    @Test func noRecordCompletionIsAcceptedButRejectedPersistenceIsInert() {
        let harness = InferenceLiveCompletionHarness()
        let system = harness.makeSystem()

        let completion = system.coordinator.prepare(
            outcome: .completedWithoutRecord(result()),
            targetEradicationScanId: "original-scan",
            modelContext: nil
        )

        #expect(completion != nil)
        #expect(harness.events == [
            .replacement(
                "original-scan",
                "completed_without_record"
            ),
            .circuitSuccess,
            .telemetry("pro", "free")
        ])

        harness.resetEvents()
        #expect(
            system.coordinator.prepare(
                outcome: .persistenceRejected,
                targetEradicationScanId: "original-scan",
                modelContext: nil
            ) == nil
        )
        #expect(harness.events.isEmpty)
    }

    @Test func foregroundEventRequiresBiologicalResultAndScanId() {
        let harness = InferenceLiveCompletionHarness()
        let coordinator = harness.makeSystem().coordinator

        coordinator.publishForegroundCompletionEventIfNeeded(
            for: speciesData()
        )
        coordinator.publishForegroundCompletionEventIfNeeded(
            for: speciesData(scanId: "non-biological", isBiological: false)
        )
        coordinator.publishForegroundCompletionEventIfNeeded(
            for: speciesData(scanId: nil)
        )

        #expect(harness.events == [
            .foregroundCompletion("result-scan")
        ])
    }

    @Test func durableFinalizationAuthorizesNotificationAndMilestone() async throws {
        let harness = InferenceLiveCompletionHarness()
        let system = harness.makeSystem()
        let attempt = UUID()
        let foreground = UUID()
        let speciesData = speciesData()
        system.attemptCoordinator.activate(
            scanId: "owner-scan",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        let permit = await system.coordinator
            .finalizeQueueAndAuthorizeFollowUps(
                scanId: "owner-scan",
                attemptGeneration: attempt,
                foregroundGeneration: foreground,
                mediaPathsToKeep: ["audio.m4a", "video.mov"],
                speciesData: speciesData,
                modelContainer: nil
            )
        let acceptedPermit = try #require(permit)
        system.coordinator.sendNotificationIfEnabled(acceptedPermit)
        system.coordinator.scheduleMilestones(acceptedPermit)

        #expect(system.attemptCoordinator.activeForegroundGeneration == nil)
        #expect(harness.events == [
            .queueDeleted(
                "owner-scan",
                ["audio.m4a", "video.mov"],
                foreground
            ),
            .notificationPreferenceRead,
            .notification("Test subject", "result-scan"),
            .milestone("result-scan", "Test subject")
        ])
    }

    @Test func failedDurableFinalizationDeniesAllFollowUps() async {
        let harness = InferenceLiveCompletionHarness()
        harness.queueDeleteResult = false
        let system = harness.makeSystem()
        let attempt = UUID()
        let foreground = UUID()
        system.attemptCoordinator.activate(
            scanId: "owner-scan",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        let permit = await system.coordinator
            .finalizeQueueAndAuthorizeFollowUps(
                scanId: "owner-scan",
                attemptGeneration: attempt,
                foregroundGeneration: foreground,
                mediaPathsToKeep: [],
                speciesData: speciesData(),
                modelContainer: nil
            )

        #expect(permit == nil)
        #expect(harness.events == [
            .queueDeleted("owner-scan", [], foreground),
            .queueRetired(
                "owner-scan",
                foreground,
                true,
                "live_cleanup_failed_or_replaced"
            )
        ])
    }

    @Test func ownerReplacementDuringFinalizationDeniesFollowUps() async {
        let gate = InferenceOperationGate()
        let harness = InferenceLiveCompletionHarness()
        harness.deleteOperation = {
            await gate.wait()
            return true
        }
        let system = harness.makeSystem()
        let originalAttempt = UUID()
        let originalForeground = UUID()
        system.attemptCoordinator.activate(
            scanId: "owner-scan",
            attemptGeneration: originalAttempt,
            foregroundGeneration: originalForeground
        )

        let finalization = Task { @MainActor in
            await system.coordinator.finalizeQueueAndAuthorizeFollowUps(
                scanId: "owner-scan",
                attemptGeneration: originalAttempt,
                foregroundGeneration: originalForeground,
                mediaPathsToKeep: [],
                speciesData: speciesData(),
                modelContainer: nil
            )
        }
        await gate.waitUntilStarted()
        system.attemptCoordinator.activate(
            scanId: "replacement-scan",
            attemptGeneration: UUID(),
            foregroundGeneration: UUID()
        )
        await gate.release()

        #expect(await finalization.value == nil)
        #expect(harness.events == [
            .queueDeleted("owner-scan", [], originalForeground)
        ])
    }

    @Test func durableRetirementDuringFinalizationDeniesFollowUps() async {
        let gate = InferenceOperationGate()
        let harness = InferenceLiveCompletionHarness()
        harness.deleteOperation = {
            await gate.wait()
            return true
        }
        let system = harness.makeSystem()
        let attempt = UUID()
        let foreground = UUID()
        system.attemptCoordinator.activate(
            scanId: "owner-scan",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        let finalization = Task { @MainActor in
            await system.coordinator.finalizeQueueAndAuthorizeFollowUps(
                scanId: "owner-scan",
                attemptGeneration: attempt,
                foregroundGeneration: foreground,
                mediaPathsToKeep: [],
                speciesData: speciesData(),
                modelContainer: nil
            )
        }
        await gate.waitUntilStarted()
        system.attemptCoordinator.retireForegroundInferenceIfCurrent(
            scanId: "owner-scan",
            attemptGeneration: attempt,
            foregroundGeneration: foreground,
            resumeBackground: true,
            reason: "connectivity_handoff"
        )
        await gate.release()

        #expect(await finalization.value == nil)
        #expect(system.attemptCoordinator.activeScanId == "owner-scan")
        #expect(system.attemptCoordinator.activeAttemptGeneration == attempt)
        #expect(system.attemptCoordinator.activeForegroundGeneration == nil)
        #expect(harness.events == [
            .queueDeleted("owner-scan", [], foreground),
            .queueRetired(
                "owner-scan",
                foreground,
                true,
                "connectivity_handoff"
            )
        ])
    }

    @Test func queueLessPermitPreservesSynchronousOwnerAndPreferenceFence() throws {
        let harness = InferenceLiveCompletionHarness()
        harness.notificationsEnabled = false
        let system = harness.makeSystem()
        let attempt = UUID()
        system.attemptCoordinator.activate(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: nil
        )

        let permit = system.coordinator.authorizeQueueLessFollowUps(
            scanId: nil,
            attemptGeneration: attempt,
            speciesData: speciesData(),
            modelContainer: nil
        )
        let acceptedPermit = try #require(permit)
        system.coordinator.sendNotificationIfEnabled(acceptedPermit)
        system.coordinator.scheduleMilestones(acceptedPermit)

        #expect(harness.events == [
            .notificationPreferenceRead,
            .milestone("result-scan", "Test subject")
        ])

        system.attemptCoordinator.activate(
            scanId: "replacement-scan",
            attemptGeneration: UUID(),
            foregroundGeneration: nil
        )
        #expect(
            system.coordinator.authorizeQueueLessFollowUps(
                scanId: nil,
                attemptGeneration: attempt,
                speciesData: speciesData(),
                modelContainer: nil
            ) == nil
        )
    }

    @Test func queueLessAuthorizationCannotBypassDurableFinalization() {
        let harness = InferenceLiveCompletionHarness()
        let system = harness.makeSystem()
        let attempt = UUID()
        let foreground = UUID()
        system.attemptCoordinator.activate(
            scanId: "queued-scan",
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )

        #expect(
            system.coordinator.authorizeQueueLessFollowUps(
                scanId: "queued-scan",
                attemptGeneration: attempt,
                speciesData: speciesData(),
                modelContainer: nil
            ) == nil
        )

        system.attemptCoordinator.activate(
            scanId: nil,
            attemptGeneration: attempt,
            foregroundGeneration: foreground
        )
        #expect(
            system.coordinator.authorizeQueueLessFollowUps(
                scanId: nil,
                attemptGeneration: attempt,
                speciesData: speciesData(),
                modelContainer: nil
            ) == nil
        )
        #expect(harness.events.isEmpty)
    }

    private func result(
        isNewDiscovery: Bool = false,
        savedImagePaths: [String] = [],
        planUsed: String? = "free"
    ) -> InferenceLiveResultService.CompletedResult {
        .init(
            speciesData: speciesData(),
            isNewDiscovery: isNewDiscovery,
            savedImagePaths: savedImagePaths,
            planUsed: planUsed
        )
    }

    private func speciesData(
        scanId: String? = "result-scan",
        isBiological: Bool = true
    ) -> SpeciesData {
        SpeciesData(
            scanId: scanId,
            commonName: "Test subject",
            scientificName: "Test species",
            insightData: InsightData(
                aiReasoning: "Test observation",
                hazardType: "none"
            ),
            confidenceScore: 0.95,
            isBiological: isBiological,
            inferenceTier: "pro",
            audioFilePaths: ["audio.m4a"],
            videoFilePaths: ["video.mov"]
        )
    }
}
