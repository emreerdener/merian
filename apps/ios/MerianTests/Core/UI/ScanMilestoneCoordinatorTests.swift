import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Scan Milestone Coordinator")
struct ScanMilestoneCoordinatorTests {
    @Test func scanMilestonesWaitForProgressThenPresentInRequiredOrder() async {
        let presenter = MilestoneToastPresenter()
        var progressContinuation: CheckedContinuation<ScanMilestoneCoordinator.ProgressResolution, Never>?
        let achievement = MilestoneFeedbackTestFixtures.completedAward(.domesticDog)
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                await withCheckedContinuation { continuation in
                    progressContinuation = continuation
                }
            },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = MilestoneFeedbackTestFixtures.milestoneSpecies()
        species.isNewToMerianDictionary = true

        let task = Task {
            await coordinator.processCompletedScan(
                scanId: "ordered-scan",
                speciesData: species,
                modelContainer: nil
            )
        }

        while progressContinuation == nil {
            await Task.yield()
        }
        #expect(presenter.activeItem == nil)

        progressContinuation?.resume(returning: .success(MilestoneFeedbackTestFixtures.progressResult()))
        await task.value

        guard case .fieldTrip(let fieldTrip) = presenter.activeItem?.payload else {
            Issue.record("Expected Field trip progress first")
            return
        }
        #expect(fieldTrip.title == "Spider goal complete")
        #expect(fieldTrip.tripTitle == "Backyard Safari")
        #expect(fieldTrip.artwork == .bundledImage(name: "fieldtrip-backyard-spider"))

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .fieldTrip(let challenge) = presenter.activeItem?.payload else {
            Issue.record("Expected seasonal challenge second")
            return
        }
        #expect(challenge.destination == .fieldTripChallenge(challengeId: "challenge-1"))

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        #expect(presenter.activeItem?.award?.type == .domesticDog)

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary(let milestone) = presenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook last")
            return
        }
        #expect(milestone == .newToMerian)
    }

    @Test func scanMilestoneCoordinatorPublishesOnlyThroughInjectedEventBus() async {
        let presenter = MilestoneToastPresenter()
        let eventBus = AppEventPublisher()
        var receivedEvents: [String] = []
        let cancellable = eventBus.publisher.sink { event in
            switch event {
            case .fieldTripProgressInvalidated(let templateIds):
                receivedEvents.append("field-trip:\(templateIds.sorted().joined(separator: ","))")
            case .fieldTripChallengeProgressInvalidated(let challengeIds):
                receivedEvents.append("challenge:\(challengeIds.sorted().joined(separator: ","))")
            case .fieldTripScanContributionsInvalidated(let scanId):
                receivedEvents.append("scan:\(scanId)")
            default:
                break
            }
        }
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in .success(MilestoneFeedbackTestFixtures.progressResult()) },
            achievementResolver: { _ in [] },
            fieldTripsAvailabilityResolver: { true },
            retryDelays: [],
            eventSender: eventBus,
            presenter: presenter
        )

        await coordinator.processCompletedScan(
            scanId: "injected-event-scan",
            speciesData: nil,
            modelContainer: nil
        )

        #expect(receivedEvents == [
            "field-trip:template-1",
            "challenge:challenge-1",
            "scan:injected-event-scan"
        ])
        withExtendedLifetime(cancellable) {}
    }

    @Test func transientProgressFailureRetriesWithoutDuplicatingOtherMilestones() async {
        let presenter = MilestoneToastPresenter()
        let achievement = MilestoneFeedbackTestFixtures.completedAward(.domesticCat)
        let preferredGoal = FieldTripPreferredGoal(
            userFieldTripId: "trip-1",
            itemId: "item-1"
        )
        var resolverCalls = 0
        var receivedPreferredGoals: [FieldTripPreferredGoal?] = []
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, receivedPreferredGoal in
                resolverCalls += 1
                receivedPreferredGoals.append(receivedPreferredGoal)
                return resolverCalls == 1
                    ? .retryableFailure
                    : .success(MilestoneFeedbackTestFixtures.progressResult())
            },
            achievementResolver: { _ in [achievement] },
            retryDelays: [],
            presenter: presenter
        )
        var species = MilestoneFeedbackTestFixtures.milestoneSpecies()
        species.isNewToMerianDictionary = true

        await coordinator.processCompletedScan(
            scanId: "failed-progress-scan",
            speciesData: species,
            modelContainer: nil,
            preferredGoal: preferredGoal
        )

        #expect(presenter.activeItem?.award?.type == .domesticCat)
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected dictionary milestone after achievement")
            return
        }
        presenter.dismissActiveItem(id: presenter.activeItem?.id)

        await coordinator.processCompletedScan(
            scanId: "failed-progress-scan",
            speciesData: species,
            modelContainer: nil
        )

        guard case .fieldTrip = presenter.activeItem?.payload else {
            Issue.record("Expected Field trip progress after the retry succeeded")
            return
        }
        #expect(resolverCalls == 2)
        #expect(receivedPreferredGoals == [preferredGoal, preferredGoal])
        #expect(presenter.presentedItems.count == 2)
    }

    @Test func transientProgressFailureAutomaticallyRetries() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                resolverCalls += 1
                return resolverCalls == 1
                    ? .retryableFailure
                    : .success(MilestoneFeedbackTestFixtures.progressResult())
            },
            achievementResolver: { _ in [] },
            fieldTripsAvailabilityResolver: { true },
            retryDelays: [.milliseconds(1)],
            presenter: presenter
        )

        await coordinator.processCompletedScan(
            scanId: "automatic-retry-scan",
            speciesData: nil,
            modelContainer: nil
        )

        for _ in 0..<100 where resolverCalls < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(resolverCalls == 2)
        guard case .fieldTrip = presenter.activeItem?.payload else {
            Issue.record("Expected Field trip progress after the automatic retry")
            return
        }
    }

    @Test func accountTransitionPreventsAStaleResolverFromSchedulingRetryWork() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        var progressContinuation: CheckedContinuation<
            ScanMilestoneCoordinator.ProgressResolution,
            Never
        >?
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                resolverCalls += 1
                return await withCheckedContinuation { continuation in
                    progressContinuation = continuation
                }
            },
            achievementResolver: { _ in [] },
            retryDelays: [.milliseconds(1)],
            presenter: presenter
        )

        let processingTask = Task {
            await coordinator.processCompletedScan(
                scanId: "stale-session-retry-scan",
                speciesData: nil,
                modelContainer: nil
            )
        }
        while progressContinuation == nil {
            await Task.yield()
        }

        coordinator.beginAccountSession(
            accountID: "replacement-account",
            origin: .runtimeTransition,
            now: Date()
        )
        progressContinuation?.resume(returning: .retryableFailure)
        await processingTask.value
        try? await Task.sleep(for: .milliseconds(25))

        #expect(resolverCalls == 1)
        #expect(presenter.presentedItems.isEmpty)
    }

    @Test func accountTransitionAllowsCurrentSessionToProcessTheSameScanKey() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        var firstContinuation: CheckedContinuation<
            ScanMilestoneCoordinator.ProgressResolution,
            Never
        >?
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                resolverCalls += 1
                if resolverCalls == 1 {
                    return await withCheckedContinuation { continuation in
                        firstContinuation = continuation
                    }
                }
                return .terminalFailure
            },
            achievementResolver: { _ in [] },
            retryDelays: [],
            presenter: presenter
        )

        let staleTask = Task {
            await coordinator.processCompletedScan(
                scanId: "SESSION-SCAN",
                speciesData: nil,
                modelContainer: nil
            )
        }
        while firstContinuation == nil {
            await Task.yield()
        }

        coordinator.beginAccountSession(
            accountID: "replacement-account",
            origin: .runtimeTransition,
            now: Date()
        )
        await coordinator.processCompletedScan(
            scanId: "session-scan",
            speciesData: nil,
            modelContainer: nil
        )

        firstContinuation?.resume(returning: .terminalFailure)
        await staleTask.value

        #expect(resolverCalls == 2)
        #expect(presenter.presentedItems.isEmpty)
    }

    @Test func sessionAdvanceRetainsCompletedScanDeduplication() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                resolverCalls += 1
                return .terminalFailure
            },
            achievementResolver: { _ in [] },
            retryDelays: [],
            presenter: presenter
        )

        await coordinator.processCompletedScan(
            scanId: "SESSION-DEDUP-SCAN",
            speciesData: nil,
            modelContainer: nil
        )
        coordinator.advanceSession(now: Date())
        await coordinator.processCompletedScan(
            scanId: "session-dedup-scan",
            speciesData: nil,
            modelContainer: nil
        )

        #expect(resolverCalls == 1)
    }

    @Test func progressRetryTasksStayGloballyBounded() async {
        let presenter = MilestoneToastPresenter()
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in .retryableFailure },
            achievementResolver: { _ in [] },
            retryDelays: [.seconds(60)],
            maximumRetryTaskCount: 2,
            presenter: presenter
        )

        for scanIndex in 1...3 {
            await coordinator.processCompletedScan(
                scanId: "retry-scan-\(scanIndex)",
                speciesData: nil,
                modelContainer: nil
            )
        }

        #expect(coordinator.pendingRetryTaskCountForTesting == 2)

        coordinator.advanceSession(now: Date())
        #expect(coordinator.pendingRetryTaskCountForTesting == 0)
    }

    @Test func terminalProgressFailureFinalizesWithoutRetrying() async {
        let presenter = MilestoneToastPresenter()
        let achievement = MilestoneFeedbackTestFixtures.completedAward(.domesticDog)
        var resolverCalls = 0
        var achievementCalls = 0
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                resolverCalls += 1
                return .terminalFailure
            },
            achievementResolver: { _ in
                achievementCalls += 1
                return [achievement]
            },
            fieldTripsAvailabilityResolver: { true },
            retryDelays: [.milliseconds(1)],
            presenter: presenter
        )

        await coordinator.processCompletedScan(
            scanId: "terminal-progress-scan",
            speciesData: nil,
            modelContainer: nil
        )
        await coordinator.processCompletedScan(
            scanId: "terminal-progress-scan",
            speciesData: nil,
            modelContainer: nil
        )

        #expect(resolverCalls == 1)
        #expect(achievementCalls == 1)
        #expect(presenter.presentedItems.count == 1)
        #expect(presenter.activeItem?.award?.type == .domesticDog)
    }

    @Test func noMatchingProgressStillReleasesAchievementAndDictionaryMilestones() async {
        let presenter = MilestoneToastPresenter()
        let achievement = MilestoneFeedbackTestFixtures.completedAward(.domesticDog)
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                .success(FieldTripProgressResult(fieldTripUpdates: [], challengeUpdates: []))
            },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = MilestoneFeedbackTestFixtures.milestoneSpecies()
        species.isNewToMerianDictionary = true

        await coordinator.processCompletedScan(
            scanId: "no-match-scan",
            speciesData: species,
            modelContainer: nil
        )

        #expect(presenter.activeItem?.award?.type == .domesticDog)
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected dictionary milestone after achievement")
            return
        }
    }

    @Test func disabledFieldTripsSkipProgressWithoutInterruptingOtherMilestones() async {
        let presenter = MilestoneToastPresenter()
        var progressResolverCalls = 0
        let achievement = MilestoneFeedbackTestFixtures.completedAward(.domesticDog)
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                progressResolverCalls += 1
                return .retryableFailure
            },
            achievementResolver: { _ in [achievement] },
            fieldTripsAvailabilityResolver: { false },
            presenter: presenter
        )
        var species = MilestoneFeedbackTestFixtures.milestoneSpecies()
        species.isNewToMerianDictionary = true

        await coordinator.processCompletedScan(
            scanId: "disabled-field-trips-scan",
            speciesData: species,
            modelContainer: nil
        )

        #expect(progressResolverCalls == 0)
        #expect(presenter.activeItem?.award?.type == .domesticDog)
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected dictionary milestone after ordinary achievement")
            return
        }
    }

    @Test func finalFieldTripProgressPresentsAchievementBeforeDictionary() async {
        let presenter = MilestoneToastPresenter()
        let achievementProgress = FirstFieldTripAchievementProgress(
            kind: .seasonalChallenge,
            completedAt: "2026-07-18T14:00:00Z",
            templateSlug: nil,
            challengeId: "challenge-1"
        )
        let fieldTripProgress = MilestoneFeedbackTestFixtures.progressResult()
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in
                .success(FieldTripProgressResult(
                    fieldTripUpdates: fieldTripProgress.fieldTripUpdates,
                    challengeUpdates: fieldTripProgress.challengeUpdates,
                    firstFieldTripAchievement: achievementProgress,
                    firstFieldTripAchievementNewlyUnlocked: true
                ))
            },
            achievementResolver: { _ in [] },
            fieldTripsAvailabilityResolver: { true },
            presenter: presenter
        )
        var species = MilestoneFeedbackTestFixtures.milestoneSpecies()
        species.isNewToMerianDictionary = true

        await coordinator.processCompletedScan(
            scanId: "first-field-trip-unlock",
            speciesData: species,
            modelContainer: nil
        )

        guard case .fieldTrip = presenter.activeItem?.payload else {
            Issue.record("Expected standard Field trip progress first")
            return
        }
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .fieldTrip = presenter.activeItem?.payload else {
            Issue.record("Expected challenge progress second")
            return
        }
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        #expect(presenter.activeItem?.award?.type == .firstFieldTrip)
        #expect(
            presenter.activeItem?.award?.destination
                == .fieldTripChallenge(challengeId: "challenge-1")
        )
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected dictionary milestone after Field trip achievement")
            return
        }
    }

    @Test func coordinatorRoutesLiveEffectsThroughInjectedDependencies() async {
        let presenter = MilestoneToastPresenter()
        let achievementProgress = FirstFieldTripAchievementProgress(
            kind: .standardOuting,
            completedAt: "2026-07-18T14:00:00Z",
            templateSlug: "backyard_safari",
            challengeId: nil
        )
        let progress = FieldTripProgressResult(
            fieldTripUpdates: [],
            challengeUpdates: [],
            firstFieldTripAchievement: achievementProgress,
            firstFieldTripAchievementNewlyUnlocked: true
        )
        var acknowledgedScanIDs: [String] = []
        var cachedAccountIDs: [String] = []
        var evaluatedAwardTypes: [AchievementType] = []
        let dependencies = ScanMilestoneCoordinator.Dependencies(
            currentAccountID: { "account-a" },
            acknowledgeFieldTripProgress: { scanID in
                acknowledgedScanIDs.append(scanID)
            },
            saveFirstFieldTripAchievement: { _, accountID in
                cachedAccountIDs.append(accountID)
            },
            evaluateAchievementsForNotifications: { awards in
                evaluatedAwardTypes.append(contentsOf: awards.map(\.type))
                return awards
            }
        )
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { _, _ in .success(progress) },
            achievementResolver: { _ in [] },
            fieldTripsAvailabilityResolver: { true },
            retryDelays: [],
            presenter: presenter,
            dependencies: dependencies
        )

        await coordinator.processCompletedScan(
            scanId: "injected-effects-scan",
            speciesData: nil,
            modelContainer: nil
        )

        #expect(acknowledgedScanIDs == ["injected-effects-scan"])
        #expect(cachedAccountIDs == ["account-a"])
        #expect(evaluatedAwardTypes == [.firstFieldTrip])
        #expect(presenter.activeItem?.award?.type == .firstFieldTrip)
    }

    @Test func liveAndBackgroundCompletionRaceProcessesScanOnce() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        var resolvedScanIds: [String] = []
        var progressContinuation: CheckedContinuation<ScanMilestoneCoordinator.ProgressResolution, Never>?
        let coordinator = MilestoneFeedbackTestFixtures.coordinator(
            progressResolver: { scanId, _ in
                resolverCalls += 1
                resolvedScanIds.append(scanId)
                return await withCheckedContinuation { continuation in
                    progressContinuation = continuation
                }
            },
            achievementResolver: { _ in [] },
            retryDelays: [],
            presenter: presenter
        )

        let liveTask = Task {
            await coordinator.processCompletedScan(
                scanId: "RACE-SCAN",
                speciesData: nil,
                modelContainer: nil
            )
        }
        while progressContinuation == nil {
            await Task.yield()
        }
        let backgroundTask = Task {
            await coordinator.processCompletedScan(
                scanId: "race-scan",
                speciesData: nil,
                modelContainer: nil
            )
        }

        await backgroundTask.value
        progressContinuation?.resume(returning: .retryableFailure)
        await liveTask.value

        #expect(resolverCalls == 1)
        #expect(resolvedScanIds == ["RACE-SCAN"])
    }
}
