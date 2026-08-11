import Foundation
import SwiftUI
@testable import Merian
import Testing

@MainActor
private var systemPresenter: MilestoneToastPresenter {
    AppDIContainer.shared.milestoneToastPresenter
}

@MainActor
@Suite(.serialized)
struct AchievementToastPresenterTests {
    private let unlockedAchievementsKey = "Merian_UnlockedAchievements"

    init() {
        systemPresenter.resetForTesting()
        GamificationManager.shared.unlockedAchievements = []
        UserDefaults.standard.removeObject(forKey: unlockedAchievementsKey)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
    }

    @Test func previewAchievementUnlockPresentsWithoutPersistingUnlock() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        systemPresenter.previewAchievementUnlock(completedAward(.domesticCat))

        #expect(systemPresenter.activeItem?.award?.type == .domesticCat)
        #expect(systemPresenter.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func queuedAchievementUnlocksPresentFIFO() {
        systemPresenter.previewAchievementUnlock(completedAward(.domesticCat))
        systemPresenter.previewAchievementUnlock(completedAward(.domesticDog))
        systemPresenter.previewAchievementUnlock(completedAward(.nocturnal))

        #expect(systemPresenter.activeItem?.award?.type == .domesticCat)
        #expect(systemPresenter.queuedItemCount == 2)
        let presentedIDs = systemPresenter.presentedItems.map(\.id)
        #expect(presentedIDs.count == 3)

        let firstID = systemPresenter.activeItem?.id
        systemPresenter.dismissActiveItem(id: firstID)

        #expect(systemPresenter.activeItem?.award?.type == .domesticDog)
        #expect(systemPresenter.queuedItemCount == 1)
        #expect(
            systemPresenter.presentedItems.map(\.id)
                == Array(presentedIDs.dropFirst())
        )

        let secondID = systemPresenter.activeItem?.id
        systemPresenter.dismissActiveItem(id: secondID)

        #expect(systemPresenter.activeItem?.award?.type == .nocturnal)
        #expect(systemPresenter.queuedItemCount == 0)

        let thirdID = systemPresenter.activeItem?.id
        systemPresenter.dismissActiveItem(id: thirdID)

        #expect(systemPresenter.activeItem == nil)
    }

    @Test func visualMilestoneQueueIsBoundedWhileHostIsUnavailable() {
        let presenter = MilestoneToastPresenter(maximumPresentedItemCount: 2)

        let first = presenter.enqueueAchievementUnlock(completedAward(.domesticCat))
        let second = presenter.enqueueAchievementUnlock(completedAward(.domesticDog))
        let overflow = presenter.enqueueAchievementUnlock(completedAward(.nocturnal))

        guard case .enqueued = first, case .enqueued = second else {
            Issue.record("Expected the queue to accept items below its bound")
            return
        }
        #expect(overflow == .droppedOverflow)
        #expect(presenter.presentedItems.count == 2)
        #expect(presenter.activeItem?.award?.type == .domesticCat)
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        #expect(presenter.activeItem?.award?.type == .domesticDog)
    }

    @Test func duplicateMilestonesCoalesceOntoStablePresentedIdentity() {
        let presenter = MilestoneToastPresenter()
        let award = completedAward(.domesticCat)

        let first = presenter.enqueueAchievementUnlock(award)
        guard case .enqueued(let firstID) = first else {
            Issue.record("Expected the first milestone to enqueue")
            return
        }

        let duplicate = presenter.enqueueAchievementUnlock(award)

        #expect(duplicate == .coalesced(into: firstID))
        #expect(presenter.presentedItems.map(\.id) == [firstID])
    }

    @Test func accountAndSessionTransitionsFenceStaleMilestoneCallbacks() {
        let presenter = MilestoneToastPresenter()
        let now = Date(timeIntervalSince1970: 100)
        presenter.beginAccountSession(
            accountID: "account-a",
            origin: .initialRestoration,
            now: now
        )
        let accountAToken = presenter.sessionToken
        presenter.enqueueAchievementUnlock(completedAward(.domesticCat))

        presenter.beginAccountSession(
            accountID: "account-b",
            origin: .runtimeTransition,
            now: now.addingTimeInterval(1)
        )

        #expect(presenter.presentedItems.isEmpty)
        #expect(
            presenter.enqueueAchievementUnlock(
                completedAward(.domesticDog),
                expectedSession: accountAToken
            ) == .rejectedStaleSession
        )

        let accountBToken = presenter.sessionToken
        presenter.enqueueAchievementUnlock(completedAward(.domesticDog))
        presenter.advanceSession(now: now.addingTimeInterval(2))

        #expect(presenter.presentedItems.isEmpty)
        #expect(
            presenter.enqueueAchievementUnlock(
                completedAward(.nocturnal),
                expectedSession: accountBToken
            ) == .rejectedStaleSession
        )
    }

    @Test func presentationEffectsAndLifetimeAreClaimedOnceAcrossHostRemounts() {
        let presenter = MilestoneToastPresenter(automaticDismissInterval: 3.5)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        guard case .enqueued(let itemID) = presenter.enqueueAchievementUnlock(
            completedAward(.domesticCat)
        ) else {
            Issue.record("Expected milestone to enqueue")
            return
        }

        #expect(presenter.claimPresentationEffects(id: itemID, now: startedAt))
        #expect(!presenter.claimPresentationEffects(id: itemID, now: startedAt))
        let remaining = presenter.remainingAutomaticDismissInterval(
            id: itemID,
            now: startedAt.addingTimeInterval(2)
        )
        #expect(abs((remaining ?? 0) - 1.5) < 0.001)
    }

    @Test func nestedMilestoneHostsRestoreThePreviousOwnerOnUnmount() {
        let registry = MilestoneToastHostRegistry()
        let rootHost = UUID()
        let nestedHost = UUID()

        registry.register(rootHost)
        registry.register(nestedHost)
        #expect(registry.activeHostID == nestedHost)

        registry.unregister(nestedHost)
        #expect(registry.activeHostID == rootHost)

        registry.unregister(rootHost)
        #expect(registry.activeHostID == nil)
    }

    @Test func staleMilestoneHostsCannotGrowTheRegistryWithoutBound() {
        let registry = MilestoneToastHostRegistry(maximumHostCount: 2)
        let expiredHost = UUID()
        let previousHost = UUID()
        let activeHost = UUID()

        registry.register(expiredHost)
        registry.register(previousHost)
        registry.register(activeHost)

        #expect(registry.hostIDs == [previousHost, activeHost])
        registry.unregister(activeHost)
        #expect(registry.activeHostID == previousHost)
    }

    @Test func mixedMilestoneQueuePresentsFIFO() {
        systemPresenter.previewAchievementUnlock(completedAward(.domesticCat))
        systemPresenter.previewNewToMerianMilestone()
        systemPresenter.previewAchievementUnlock(completedAward(.domesticDog))

        #expect(systemPresenter.activeItem?.award?.type == .domesticCat)
        #expect(systemPresenter.queuedItemCount == 2)

        let firstID = systemPresenter.activeItem?.id
        systemPresenter.dismissActiveItem(id: firstID)

        guard case .dictionary(let milestone) = systemPresenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook milestone to present second")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(systemPresenter.queuedItemCount == 1)

        let secondID = systemPresenter.activeItem?.id
        systemPresenter.dismissActiveItem(id: secondID)

        #expect(systemPresenter.activeItem?.award?.type == .domesticDog)
    }

    @Test func previewMilestoneStackIsDeterministicAndFIFO() {
        let presenter = systemPresenter

        presenter.previewMilestoneStack()

        guard case .fieldTrip = presenter.activeItem?.payload else {
            Issue.record("Expected Field trip progress at the front of the preview stack")
            return
        }
        #expect(presenter.queuedItemCount == 2)

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        #expect(presenter.activeItem?.award?.type == .domesticDog)
        #expect(presenter.queuedItemCount == 1)

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook at the back of the preview stack")
            return
        }
        #expect(presenter.queuedItemCount == 0)
    }

    @Test func visibleToastBackingLayersAreClamped() {
        #expect(ToastStackPresentation.maximumMountedPayloadCount == 1)
        #expect(ToastStackPresentation.visibleBackingLayerCount(for: -1) == 0)
        #expect(ToastStackPresentation.visibleBackingLayerCount(for: 0) == 0)
        #expect(ToastStackPresentation.visibleBackingLayerCount(for: 1) == 1)
        #expect(ToastStackPresentation.visibleBackingLayerCount(for: 2) == 2)
        #expect(ToastStackPresentation.visibleBackingLayerCount(for: 5) == 2)
    }

    @Test func stackedToastBackingSurfaceStaysVisibleWhenForegroundDismisses() {
        let stackedAlpha = renderedToastCenterAlpha(pendingItemCount: 1)
        let singleAlpha = renderedToastCenterAlpha(pendingItemCount: 0)

        #expect(stackedAlpha > 80)
        #expect(singleAlpha < 8)
    }

    @Test func milestoneStackPresentationKeepsOnlyTheActivePayloadAndReportsQueueDepth() {
        let presenter = systemPresenter
        presenter.previewMilestoneStack()

        guard let presentation = MilestoneToastStackPresentation.resolve(
            presenter.presentedItems
        ) else {
            Issue.record("Expected a milestone stack presentation")
            return
        }

        #expect(presentation.activeItem.id == presenter.presentedItems.first?.id)
        #expect(presentation.pendingItemCount == 2)
        #expect(
            ToastStackPresentation.visibleBackingLayerCount(
                for: presentation.pendingItemCount
            ) == 2
        )
    }

    @Test func milestoneToastDragCommitsInEveryDirection() {
        let distance = MilestoneToastDismissalGesture.commitDistance

        #expect(MilestoneToastDismissalGesture.hasReachedCommitDistance(
            CGSize(width: distance, height: 0)
        ))
        #expect(MilestoneToastDismissalGesture.hasReachedCommitDistance(
            CGSize(width: -distance, height: 0)
        ))
        #expect(MilestoneToastDismissalGesture.hasReachedCommitDistance(
            CGSize(width: 0, height: distance)
        ))
        #expect(MilestoneToastDismissalGesture.hasReachedCommitDistance(
            CGSize(width: 0, height: -distance)
        ))
    }

    @Test func milestoneToastQuickFlickUsesProjectedDistance() {
        #expect(MilestoneToastDismissalGesture.shouldDismiss(
            translation: CGSize(width: 20, height: 0),
            predictedEndTranslation: CGSize(
                width: MilestoneToastDismissalGesture.projectedCommitDistance,
                height: 0
            )
        ))
        #expect(!MilestoneToastDismissalGesture.shouldDismiss(
            translation: CGSize(width: 20, height: 20),
            predictedEndTranslation: CGSize(width: 80, height: 80)
        ))
    }

    @Test func milestoneToastDragLocksToItsDominantAxis() {
        let horizontal = CGSize(width: -90, height: 55)
        let vertical = CGSize(width: 40, height: 100)
        let diagonalBelowAxisThreshold = CGSize(width: 70, height: 70)

        let horizontalAxis = MilestoneToastDismissalGesture.axis(for: horizontal)
        let verticalAxis = MilestoneToastDismissalGesture.axis(for: vertical)
        let constrainedDiagonal = MilestoneToastDismissalGesture.constrainedTranslation(
            diagonalBelowAxisThreshold,
            to: MilestoneToastDismissalGesture.axis(for: diagonalBelowAxisThreshold)
        )

        #expect(horizontalAxis == .horizontal)
        #expect(verticalAxis == .vertical)
        #expect(MilestoneToastDismissalGesture.constrainedTranslation(
            horizontal,
            to: horizontalAxis
        ) == CGSize(width: -90, height: 0))
        #expect(MilestoneToastDismissalGesture.constrainedTranslation(
            vertical,
            to: verticalAxis
        ) == CGSize(width: 0, height: 100))
        #expect(!MilestoneToastDismissalGesture.hasReachedCommitDistance(constrainedDiagonal))
    }

    @Test func milestoneToastDismissalKeepsFlickDirectionOffscreen() {
        let offset = MilestoneToastDismissalGesture.offscreenOffset(
            translation: CGSize(width: 20, height: 0),
            predictedEndTranslation: CGSize(width: 240, height: 0)
        )

        #expect(offset.width > 0)
        #expect(offset.height == 0)
        #expect(abs(MilestoneToastDismissalGesture.distance(for: offset)
            - MilestoneToastDismissalGesture.offscreenDistance) < 0.001)
    }

    private func renderedToastCenterAlpha(pendingItemCount: Int) -> UInt8 {
        let size = CGSize(width: 320, height: 140)
        let view = ToastBanner(
            onDismiss: nil,
            pendingItemCount: pendingItemCount,
            foregroundTransform: ToastBannerForegroundTransform(
                offset: CGSize(width: 1_000, height: 0),
                opacity: 0
            )
        ) {
            Color.clear.frame(width: 120, height: 60)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage?.cgImage,
              let centerPixel = image.cropping(to: CGRect(
                  x: CGFloat(image.width / 2),
                  y: CGFloat(image.height / 2),
                  width: 1,
                  height: 1
              )) else {
            Issue.record("Expected the toast renderer to produce a center pixel")
            return 0
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Expected a pixel-sampling context")
            return 0
        }

        context.draw(centerPixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[3]
    }

    @Test func completedAchievementUnlockReturnsTypedPresentationPayloadWhenEnabled() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [completedAward(.domesticDog)]
        )

        #expect(eligible.map(\.type) == [.domesticDog])
        #expect(systemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func legacyDomesticPetAchievementCompletionIsPersistedWithoutToast() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            completedAward(.domesticCat, lastInteractionDate: legacyDomesticPetScanDate)
        ])

        #expect(eligible.isEmpty)
        #expect(systemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    @Test func legacyCatAndFreshDogOnlyReturnsFreshDog() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            completedAward(.domesticCat, lastInteractionDate: legacyDomesticPetScanDate),
            completedAward(.domesticDog, lastInteractionDate: freshDomesticPetScanDate)
        ])

        #expect(eligible.map(\.type) == [.domesticDog])
        #expect(systemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func legacyUnlockWithFreshRepeatScanIsPersistedWithoutToast() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            completedAward(
                .domesticDog,
                lastInteractionDate: freshDomesticPetScanDate,
                unlockedAt: legacyDomesticPetScanDate
            )
        ])

        #expect(eligible.isEmpty)
        #expect(systemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func completedAchievementUnlockIsNotPresentationEligibleWhenNotificationsAreDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [completedAward(.domesticCat)]
        )

        #expect(eligible.isEmpty)
        #expect(systemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    @Test func previewNewToMerianMilestonePresentsWithoutPersistingUnlock() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        systemPresenter.previewNewToMerianMilestone()

        guard case .dictionary(let milestone) = systemPresenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook milestone")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(systemPresenter.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func scanMilestonesWaitForProgressThenPresentInRequiredOrder() async {
        let presenter = MilestoneToastPresenter()
        var progressContinuation: CheckedContinuation<ScanMilestoneCoordinator.ProgressResolution, Never>?
        let achievement = completedAward(.domesticDog)
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _, _ in
                await withCheckedContinuation { continuation in
                    progressContinuation = continuation
                }
            },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = milestoneSpecies()
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

        progressContinuation?.resume(returning: .success(progressResult()))
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

    @Test func transientProgressFailureRetriesWithoutDuplicatingOtherMilestones() async {
        let presenter = MilestoneToastPresenter()
        let achievement = completedAward(.domesticCat)
        let preferredGoal = FieldTripPreferredGoal(
            userFieldTripId: "trip-1",
            itemId: "item-1"
        )
        var resolverCalls = 0
        var receivedPreferredGoals: [FieldTripPreferredGoal?] = []
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _, receivedPreferredGoal in
                resolverCalls += 1
                receivedPreferredGoals.append(receivedPreferredGoal)
                return resolverCalls == 1
                    ? .retryableFailure
                    : .success(progressResult())
            },
            achievementResolver: { _ in [achievement] },
            retryDelays: [],
            presenter: presenter
        )
        var species = milestoneSpecies()
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
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _, _ in
                resolverCalls += 1
                return resolverCalls == 1
                    ? .retryableFailure
                    : .success(progressResult())
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
        let coordinator = ScanMilestoneCoordinator(
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
        let coordinator = ScanMilestoneCoordinator(
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
        let coordinator = ScanMilestoneCoordinator(
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
        let coordinator = ScanMilestoneCoordinator(
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
        let achievement = completedAward(.domesticDog)
        var resolverCalls = 0
        var achievementCalls = 0
        let coordinator = ScanMilestoneCoordinator(
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
        let achievement = completedAward(.domesticDog)
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _, _ in
                .success(FieldTripProgressResult(fieldTripUpdates: [], challengeUpdates: []))
            },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = milestoneSpecies()
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
        let achievement = completedAward(.domesticDog)
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _, _ in
                progressResolverCalls += 1
                return .retryableFailure
            },
            achievementResolver: { _ in [achievement] },
            fieldTripsAvailabilityResolver: { false },
            presenter: presenter
        )
        var species = milestoneSpecies()
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
        let fieldTripProgress = progressResult()
        let coordinator = ScanMilestoneCoordinator(
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
        var species = milestoneSpecies()
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

    @Test func firstFieldTripAchievementNotificationIsDeduplicated() {
        let progress = FirstFieldTripAchievementProgress(
            kind: .standardOuting,
            completedAt: "2026-07-18T14:00:00Z",
            templateSlug: "backyard_safari",
            challengeId: nil
        )
        guard let award = progress.awardPayload else {
            Issue.record("Expected a valid first Field trip award")
            return
        }

        let first = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [award]
        )
        let duplicate = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [award]
        )

        #expect(first.map(\.type) == [.firstFieldTrip])
        #expect(duplicate.isEmpty)
    }

    @Test func liveAndBackgroundCompletionRaceProcessesScanOnce() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        var resolvedScanIds: [String] = []
        var progressContinuation: CheckedContinuation<ScanMilestoneCoordinator.ProgressResolution, Never>?
        let coordinator = ScanMilestoneCoordinator(
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

    @Test func progressMappingKeepsStandardBeforeChallengeAndUsesGoalPrompt() {
        let result = progressResult(
            challengeCommonName: "   ",
            challengePrompt: "Bee or wasp"
        )

        let milestones = ScanMilestoneCoordinator.milestones(from: result)

        #expect(milestones.count == 2)
        #expect(milestones[0].tripTitle == "Backyard Safari")
        #expect(milestones[0].goalLabel == "Spider")
        #expect(milestones[0].title == "Spider goal complete")
        #expect(milestones[0].artwork == .bundledImage(name: "fieldtrip-backyard-spider"))
        #expect(milestones[0].destination == .fieldTrip(templateId: "template-1", checklistItemId: "item-1"))
        #expect(milestones[1].tripTitle == "Summer pollinators")
        #expect(milestones[1].goalLabel == "Bee or wasp")
        #expect(milestones[1].artwork == .systemSymbol(name: "binoculars.fill"))
        #expect(milestones[1].destination == .fieldTripChallenge(challengeId: "challenge-1"))
    }

    @Test func progressMappingIgnoresUpdatesWithoutNewlyCompletedItems() {
        let result = progressResult(standardIncludesNewItem: false)

        let milestones = ScanMilestoneCoordinator.milestones(from: result)

        #expect(milestones.count == 1)
        #expect(milestones[0].tripTitle == "Summer pollinators")
        #expect(milestones[0].destination == .fieldTripChallenge(challengeId: "challenge-1"))
    }

    private var legacyDomesticPetScanDate: Date {
        Date(timeIntervalSince1970: 1_783_119_600)
    }

    private var freshDomesticPetScanDate: Date {
        Date(timeIntervalSince1970: 1_783_126_800)
    }

    private func completedAward(
        _ type: AchievementType,
        lastInteractionDate: Date = Date(),
        unlockedAt: Date? = nil
    ) -> AwardPayload {
        AwardPayload(
            type: type,
            currentCount: type.definition.targetCount,
            lastInteractionDate: lastInteractionDate,
            unlockedAt: unlockedAt ?? lastInteractionDate
        )
    }

    private func milestoneSpecies() -> SpeciesData {
        SpeciesData(
            scanId: "milestone-scan",
            commonName: "Vine Sphinx",
            scientificName: "Eumorpha vitis",
            insightData: InsightData(aiReasoning: "A sphinx moth.", hazardType: "none"),
            confidenceScore: 0.97,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
    }

    private func progressResult(
        challengeCommonName: String? = "Bumble Bee",
        challengePrompt: String = "Bee",
        standardIncludesNewItem: Bool = true
    ) -> FieldTripProgressResult {
        let standardItem = FieldTripProgressCompletedItem(
            itemId: "item-1",
            prompt: "Spider",
            commonName: "Vine Sphinx",
            scientificName: "Eumorpha vitis",
            completedAt: "2026-07-18T14:00:00Z"
        )
        let challengeItem = FieldTripProgressCompletedItem(
            itemId: "challenge-item-1",
            prompt: challengePrompt,
            commonName: challengeCommonName,
            scientificName: "Bombus impatiens",
            completedAt: "2026-07-18T14:00:00Z"
        )

        return FieldTripProgressResult(
            fieldTripUpdates: [
                FieldTripProgressUpdate(
                    userFieldTripId: "trip-1",
                    templateId: "template-1",
                    slug: "backyard_safari",
                    title: "Backyard Safari",
                    currentLevelNumber: 2,
                    currentLevelTitle: "Level 2",
                    completedCount: 0,
                    targetCount: 6,
                    isComplete: false,
                    creditedLevelNumber: 1,
                    creditedLevelTitle: "Level 1",
                    creditedCompletedCount: 4,
                    creditedTargetCount: 4,
                    newlyCompletedItems: standardIncludesNewItem ? [standardItem] : [],
                    removedItemIds: nil
                )
            ],
            challengeUpdates: [
                FieldTripChallengeProgressUpdate(
                    participationId: "participation-1",
                    challengeId: "challenge-1",
                    slug: "summer_pollinators",
                    title: "Summer pollinators",
                    currentLevelNumber: 1,
                    currentLevelTitle: "Level 1",
                    completedCount: 2,
                    targetCount: 4,
                    isComplete: false,
                    badgeAwardedAt: nil,
                    suggestedHashtags: ["summerpollinators"],
                    creditedLevelNumber: 1,
                    creditedLevelTitle: "Level 1",
                    creditedCompletedCount: 2,
                    creditedTargetCount: 4,
                    newlyCompletedItems: [challengeItem],
                    removedItemIds: nil
                )
            ]
        )
    }
}
