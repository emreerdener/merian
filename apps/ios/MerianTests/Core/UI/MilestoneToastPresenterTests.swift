import Foundation
@testable import Merian
import SwiftUI
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.gamificationManager))
struct MilestoneToastPresenterTests {
    private let unlockedAchievementsKey = UserDefaultsKeys.unlockedAchievements

    init() {
        resetMilestoneFeedbackGlobalState()
    }

    @Test func previewAchievementUnlockPresentsWithoutPersistingUnlock() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        milestoneFeedbackSystemPresenter.previewAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticCat))

        #expect(milestoneFeedbackSystemPresenter.activeItem?.award?.type == .domesticCat)
        #expect(milestoneFeedbackSystemPresenter.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func queuedAchievementUnlocksPresentFIFO() {
        milestoneFeedbackSystemPresenter.previewAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticCat))
        milestoneFeedbackSystemPresenter.previewAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticDog))
        milestoneFeedbackSystemPresenter.previewAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.nocturnal))

        #expect(milestoneFeedbackSystemPresenter.activeItem?.award?.type == .domesticCat)
        #expect(milestoneFeedbackSystemPresenter.queuedItemCount == 2)
        let presentedIDs = milestoneFeedbackSystemPresenter.presentedItems.map(\.id)
        #expect(presentedIDs.count == 3)

        let firstID = milestoneFeedbackSystemPresenter.activeItem?.id
        milestoneFeedbackSystemPresenter.dismissActiveItem(id: firstID)

        #expect(milestoneFeedbackSystemPresenter.activeItem?.award?.type == .domesticDog)
        #expect(milestoneFeedbackSystemPresenter.queuedItemCount == 1)
        #expect(
            milestoneFeedbackSystemPresenter.presentedItems.map(\.id)
                == Array(presentedIDs.dropFirst())
        )

        let secondID = milestoneFeedbackSystemPresenter.activeItem?.id
        milestoneFeedbackSystemPresenter.dismissActiveItem(id: secondID)

        #expect(milestoneFeedbackSystemPresenter.activeItem?.award?.type == .nocturnal)
        #expect(milestoneFeedbackSystemPresenter.queuedItemCount == 0)

        let thirdID = milestoneFeedbackSystemPresenter.activeItem?.id
        milestoneFeedbackSystemPresenter.dismissActiveItem(id: thirdID)

        #expect(milestoneFeedbackSystemPresenter.activeItem == nil)
    }

    @Test func visualMilestoneQueueIsBoundedWhileHostIsUnavailable() {
        let presenter = MilestoneToastPresenter(maximumPresentedItemCount: 2)

        let first = presenter.enqueueAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticCat))
        let second = presenter.enqueueAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticDog))
        let overflow = presenter.enqueueAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.nocturnal))

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
        let award = MilestoneFeedbackTestFixtures.completedAward(.domesticCat)

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
        presenter.enqueueAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticCat))

        presenter.beginAccountSession(
            accountID: "account-b",
            origin: .runtimeTransition,
            now: now.addingTimeInterval(1)
        )

        #expect(presenter.presentedItems.isEmpty)
        #expect(
            presenter.enqueueAchievementUnlock(
                MilestoneFeedbackTestFixtures.completedAward(.domesticDog),
                expectedSession: accountAToken
            ) == .rejectedStaleSession
        )

        let accountBToken = presenter.sessionToken
        presenter.enqueueAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticDog))
        presenter.advanceSession(now: now.addingTimeInterval(2))

        #expect(presenter.presentedItems.isEmpty)
        #expect(
            presenter.enqueueAchievementUnlock(
                MilestoneFeedbackTestFixtures.completedAward(.nocturnal),
                expectedSession: accountBToken
            ) == .rejectedStaleSession
        )
    }

    @Test func presentationEffectsAndLifetimeAreClaimedOnceAcrossHostRemounts() {
        let presenter = MilestoneToastPresenter(automaticDismissInterval: 3.5)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        guard case .enqueued(let itemID) = presenter.enqueueAchievementUnlock(
            MilestoneFeedbackTestFixtures.completedAward(.domesticCat)
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
        milestoneFeedbackSystemPresenter.previewAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticCat))
        milestoneFeedbackSystemPresenter.previewNewToMerianMilestone()
        milestoneFeedbackSystemPresenter.previewAchievementUnlock(MilestoneFeedbackTestFixtures.completedAward(.domesticDog))

        #expect(milestoneFeedbackSystemPresenter.activeItem?.award?.type == .domesticCat)
        #expect(milestoneFeedbackSystemPresenter.queuedItemCount == 2)

        let firstID = milestoneFeedbackSystemPresenter.activeItem?.id
        milestoneFeedbackSystemPresenter.dismissActiveItem(id: firstID)

        guard case .dictionary(let milestone) = milestoneFeedbackSystemPresenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook milestone to present second")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(milestoneFeedbackSystemPresenter.queuedItemCount == 1)

        let secondID = milestoneFeedbackSystemPresenter.activeItem?.id
        milestoneFeedbackSystemPresenter.dismissActiveItem(id: secondID)

        #expect(milestoneFeedbackSystemPresenter.activeItem?.award?.type == .domesticDog)
    }

    @Test func previewMilestoneStackIsDeterministicAndFIFO() {
        let presenter = milestoneFeedbackSystemPresenter

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
        let presenter = milestoneFeedbackSystemPresenter
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
}
