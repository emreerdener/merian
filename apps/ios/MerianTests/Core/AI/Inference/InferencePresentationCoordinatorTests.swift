import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Inference Presentation Lifecycle Coordinator")
struct InferencePresentationCoordinatorTests {
    @Test func preparedVisualHandoffUsesGenericPhrasesWithoutLiveMedia() throws {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        let genericPhrases = ["Analyzing subject", "Checking habitat"]
        var currentCheckCount = 0

        coordinator.prepare(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )
        let handoff = try #require(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .prepared(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in
                currentCheckCount += 1
                return false
            },
            activeMediaItemCount: 2,
            activeVisualPhrases: ["Analyzing amber wings"],
            preparedVisualPhrases: genericPhrases
        ))

        #expect(handoff.scanId == "scan-a")
        #expect(handoff.scanningPhrases == genericPhrases)
        #expect(!handoff.carriesLiveMedia)
        #expect(currentCheckCount == 0)
        #expect(coordinator.scanningPhrases(for: "SCAN-A") == genericPhrases)
        #expect(coordinator.hasVisualQueueHandoff(for: "scan-a"))
        #expect(!coordinator.hasLiveMedia(for: "scan-a"))
    }

    @Test func activeVisualHandoffRequiresExactOwnerAndCurrentAttempt() throws {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        let phrases = ["Analyzing spotted wings"]
        var currentCheckCount = 0

        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )

        #expect(coordinator.transitionToQueue(
            scanId: "scan-b",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in
                currentCheckCount += 1
                return true
            },
            activeMediaItemCount: 1,
            activeVisualPhrases: phrases,
            preparedVisualPhrases: []
        ) == nil)
        #expect(currentCheckCount == 0)

        #expect(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in
                currentCheckCount += 1
                return false
            },
            activeMediaItemCount: 1,
            activeVisualPhrases: phrases,
            preparedVisualPhrases: []
        ) == nil)
        #expect(currentCheckCount == 1)

        let handoff = try #require(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { scanId, attemptGeneration in
                currentCheckCount += 1
                return scanId == "scan-a" && attemptGeneration == generation
            },
            activeMediaItemCount: 1,
            activeVisualPhrases: phrases,
            preparedVisualPhrases: []
        ))

        #expect(currentCheckCount == 2)
        #expect(handoff.scanningPhrases == phrases)
        #expect(handoff.carriesLiveMedia)
        #expect(coordinator.hasLiveMedia(for: "SCAN-A"))

        #expect(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in true },
            activeMediaItemCount: 1,
            activeVisualPhrases: phrases,
            preparedVisualPhrases: []
        ) == nil)
        #expect(coordinator.scanningPhrases(for: "scan-a").isEmpty)
        #expect(!coordinator.hasVisualQueueHandoff(for: "scan-a"))
        #expect(!coordinator.hasLiveMedia(for: "scan-a"))
    }

    @Test func nonVisualHandoffNeverCarriesVisualContext() throws {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        coordinator.activate(
            scanId: "audio-scan",
            attemptGeneration: generation,
            modality: .nonVisual
        )

        let handoff = try #require(coordinator.transitionToQueue(
            scanId: "audio-scan",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in true },
            activeMediaItemCount: 3,
            activeVisualPhrases: ["Visual phrase"],
            preparedVisualPhrases: ["Generic phrase"]
        ))

        #expect(handoff.scanningPhrases.isEmpty)
        #expect(!handoff.carriesLiveMedia)
        #expect(!coordinator.hasVisualQueueHandoff(for: "audio-scan"))
        #expect(!coordinator.hasLiveMedia(for: "audio-scan"))
    }

    @Test func activeOwnerFinishesOnlyForItsExactGeneration() {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )

        coordinator.finishActivePresentation(attemptGeneration: UUID())
        #expect(coordinator.isActiveVisual(attemptGeneration: generation))

        coordinator.finishActivePresentation(attemptGeneration: generation)
        #expect(!coordinator.isActiveVisual(attemptGeneration: generation))
    }

    @Test func prepareAndResetReplaceEveryEphemeralPresentationOwner() {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        coordinator.prepare(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )
        coordinator.beginFirstRenderMetric(scanId: "scan-a", startedAt: 42)

        coordinator.reset()

        #expect(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .prepared(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in true },
            activeMediaItemCount: 1,
            activeVisualPhrases: ["Live"],
            preparedVisualPhrases: ["Prepared"]
        ) == nil)
        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-a") == nil)
    }

    @Test func firstRenderMetricIsExactAndConsumedOnce() {
        let coordinator = InferencePresentationCoordinator()
        coordinator.beginFirstRenderMetric(scanId: "Scan-A", startedAt: 42)

        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-b") == nil)
        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-a") == 42)
        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-a") == nil)
    }

    @Test func firstRenderMetricRebindRequiresItsExactSource() {
        let coordinator = InferencePresentationCoordinator()
        coordinator.beginFirstRenderMetric(
            scanId: "temporary-scan",
            startedAt: 42
        )

        coordinator.rebindFirstRenderMetric(
            from: "another-scan",
            to: "server-scan"
        )
        #expect(
            coordinator.consumeFirstRenderStart(scanId: "server-scan") == nil
        )

        coordinator.rebindFirstRenderMetric(
            from: "TEMPORARY-SCAN",
            to: "server-scan"
        )
        #expect(
            coordinator.consumeFirstRenderStart(scanId: "server-scan") == 42
        )
    }

    @Test func publishedResultPreservesPendingFirstRenderMetric() {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )
        coordinator.beginFirstRenderMetric(scanId: "scan-a", startedAt: 42)

        coordinator.clearForPublishedResult()

        #expect(!coordinator.isActiveVisual(attemptGeneration: generation))
        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-a") == 42)
    }

    @Test func authAdmissionClearsOwnersWhilePreservingRenderTiming() throws {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )
        _ = try #require(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in true },
            activeMediaItemCount: 1,
            activeVisualPhrases: ["Live"],
            preparedVisualPhrases: []
        ))
        coordinator.beginFirstRenderMetric(scanId: "scan-a", startedAt: 42)

        coordinator.clearForAuthTransitionAdmission()

        #expect(!coordinator.hasVisualQueueHandoff(for: "scan-a"))
        #expect(!coordinator.hasLiveMedia(for: "scan-a"))
        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-a") == 42)
    }

    @Test func authQuiescenceRejectsReentrantPresentationOwner() {
        let coordinator = InferencePresentationCoordinator()
        let generation = UUID()
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )
        #expect(coordinator.transitionToQueue(
            scanId: "scan-a",
            source: .active(attemptGeneration: generation),
            isActiveAttemptCurrent: { _, _ in true },
            activeMediaItemCount: 1,
            activeVisualPhrases: ["Live"],
            preparedVisualPhrases: []
        ) != nil)
        coordinator.activate(
            scanId: "scan-a",
            attemptGeneration: generation,
            modality: .visual
        )
        coordinator.beginFirstRenderMetric(scanId: "scan-a", startedAt: 42)

        coordinator.finishAuthTransitionQuiescence()

        #expect(!coordinator.isActiveVisual(attemptGeneration: generation))
        #expect(!coordinator.hasVisualQueueHandoff(for: "scan-a"))
        #expect(coordinator.scanningPhrases(for: "scan-a").isEmpty)
        #expect(coordinator.consumeFirstRenderStart(scanId: "scan-a") == 42)
    }
}
