import Foundation
@testable import Merian
import Testing

@Suite("Explore Audio Boost Tests")
struct ExploreAudioBoostTests {
    private final class ChangeRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [(String, Bool)] = []

        func append(_ change: (String, Bool)) {
            lock.lock()
            storage.append(change)
            lock.unlock()
        }

        func snapshot() -> [(String, Bool)] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    @Test func preferencesAreIndependentPerPost() throws {
        let suite = "ExploreAudioBoostTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExploreAudioBoostPreferenceStore(defaults: defaults)

        store.setEnabled(true, for: "cardinal-post")

        #expect(store.isEnabled(for: "cardinal-post"))
        #expect(!store.isEnabled(for: "frog-post"))
        store.setEnabled(false, for: "cardinal-post")
        #expect(!store.isEnabled(for: "cardinal-post"))
    }

    @Test func preferenceChangesNotifyVisibleSurfacesOnce() throws {
        let suite = "ExploreAudioBoostNotificationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExploreAudioBoostPreferenceStore(defaults: defaults)
        let targetPostId = "notification-post-\(UUID().uuidString)"
        let recorder = ChangeRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: ExploreAudioBoostPreferenceStore.didChangeNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let postId = notification.userInfo?[ExploreAudioBoostPreferenceStore.postIdUserInfoKey] as? String,
                  postId == targetPostId,
                  let enabled = notification.userInfo?[ExploreAudioBoostPreferenceStore.enabledUserInfoKey] as? Bool else {
                return
            }
            recorder.append((postId, enabled))
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.setEnabled(true, for: targetPostId)
        store.setEnabled(true, for: targetPostId)
        store.setEnabled(false, for: targetPostId)

        let changes = recorder.snapshot()
        #expect(changes.count == 2)
        #expect(changes.first?.0 == targetPostId)
        #expect(changes.first?.1 == true)
        #expect(changes.last?.1 == false)
    }

    @Test func adaptiveGainIsBoundedAndPeakSafe() {
        #expect(AudioBoostProcessor.adaptiveGainDecibels(rmsDb: -50, peakDb: -30) == 18)
        #expect(AudioBoostProcessor.adaptiveGainDecibels(rmsDb: -30, peakDb: -4) == 3)
        #expect(AudioBoostProcessor.adaptiveGainDecibels(rmsDb: -12, peakDb: -0.5) == 0)
    }

    @Test func preparationFeedbackRequiresExplicitActionToken() {
        #expect(!ExploreAudioBoostFeedbackPolicy.shouldPresent(actionToken: nil))
        #expect(ExploreAudioBoostFeedbackPolicy.shouldPresent(actionToken: UUID()))
    }

    @Test func feedBoostPillPresentsShortcutUntilBoostedAudioIsReady() {
        let unboosted = ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let preparing = ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let boosted = ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )
        let boosting = ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: true,
            isPreparingBoost: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let reverting = ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: false,
            isRevertingBoost: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )

        #expect(unboosted == .boost)
        #expect(preparing == .boost)
        #expect(boosted == .boosted)
        #expect(boosting == .boosting)
        #expect(boosting?.title == "Boosting…")
        #expect(reverting == .reverting)
        #expect(reverting?.title == "Reverting…")
        #expect(unboosted?.title == "Boost audio")
        #expect(unboosted?.systemImage == "chevron.right")
        #expect(boosted?.title == "Boosted audio")
        #expect(boosted?.systemImage == nil)
        #expect(boosted?.accessibilityLabel == "Turn off audio boost")
    }

    @Test func feedBoostPillIsLimitedToInteractiveFeedAudio() {
        #expect(ExploreFeedAudioBoostPillState.resolve(
            surface: .detail,
            mediaKind: .audio,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        ) == nil)
        #expect(ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .video,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        ) == nil)
        #expect(ExploreFeedAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: false
        ) == nil)
    }

    @Test func insightBoostPillTransitionsOnlyAfterBoostedAudioIsReady() {
        let unboosted = InsightAudioBoostPillState.resolve(
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let preparing = InsightAudioBoostPillState.resolve(
            isBoostEnabled: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let boosted = InsightAudioBoostPillState.resolve(
            isBoostEnabled: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )
        let boosting = InsightAudioBoostPillState.resolve(
            isBoostEnabled: true,
            isPreparingBoost: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let reverting = InsightAudioBoostPillState.resolve(
            isBoostEnabled: false,
            isRevertingBoost: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )

        #expect(unboosted == .boost)
        #expect(preparing == .boost)
        #expect(boosted == .boosted)
        #expect(boosting == .boosting)
        #expect(boosting?.title == "Boosting…")
        #expect(reverting == .reverting)
        #expect(reverting?.title == "Reverting…")
        #expect(unboosted?.systemImage == "chevron.right")
        #expect(boosted?.systemImage == nil)
        #expect(InsightAudioBoostPillState.resolve(
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: false
        ) == nil)
    }

    @Test func insightAudioTimestampUsesElapsedAndDurationClockFormat() {
        #expect(AudioPlaybackCarouselPage.formattedTime(2.9) == "0:02")
        #expect(AudioPlaybackCarouselPage.formattedTime(75) == "1:15")
        #expect(AudioPlaybackCarouselPage.formattedTime(.nan) == "0:00")
    }

    @Test func audioSeekingNormalizesAndClampsSpectrogramPositions() {
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: -20, width: 200) == 0)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: 50, width: 200) == 0.25)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: 240, width: 200) == 1)
        #expect(AudioSpectrogramSeekingPolicy.normalizedProgress(locationX: 20, width: 0) == 0)
        #expect(AudioSpectrogramSeekingPolicy.seconds(progress: 0.5, duration: 15) == 7.5)
        #expect(AudioSpectrogramSeekingPolicy.seconds(progress: 2, duration: 15) == 15)
    }

    @Test func audioSeekingAccessibilityMovesInFiveSecondSteps() {
        #expect(AudioSpectrogramSeekingPolicy.progress(
            after: .forward,
            currentProgress: 0.25,
            duration: 20
        ) == 0.5)
        #expect(AudioSpectrogramSeekingPolicy.progress(
            after: .backward,
            currentProgress: 0.1,
            duration: 20
        ) == 0)
        #expect(AudioSpectrogramSeekingPolicy.progress(
            after: .forward,
            currentProgress: 0.9,
            duration: 20
        ) == 1)
    }

    @Test func insightPlaymarkerUsesMinimumFortyFourPointTarget() {
        #expect(AudioSpectrogramSeekingPolicy.playmarkerHitWidth == 44)
        #expect(AudioSpectrogramSeekingPolicy.playmarkerCenterX(progress: 0.5, width: 300) == 150)
    }

    @Test func returningToExploreFeedResetsVideoMutePreference() throws {
        let suite = "ExploreVideoMutePreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ExploreVideoMutePreference.key)

        ExploreVideoMutePreference.resetToMuted(defaults: defaults)

        #expect(defaults.bool(forKey: ExploreVideoMutePreference.key))
    }

    @Test func preferencesExpireAfterOneHundredEightyDays() throws {
        let suite = "ExploreAudioBoostExpiryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
        let clock = Clock()
        let store = ExploreAudioBoostPreferenceStore(defaults: defaults, now: { clock.now })

        store.setEnabled(true, for: "old-post")
        clock.now.addTimeInterval(181 * 24 * 60 * 60)

        #expect(!store.isEnabled(for: "old-post"))
    }

    @Test func preferencesKeepOnlyFiveHundredMostRecentPosts() throws {
        let suite = "ExploreAudioBoostLimitTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        final class Clock { var now = Date(timeIntervalSince1970: 2_000_000) }
        let clock = Clock()
        let store = ExploreAudioBoostPreferenceStore(defaults: defaults, now: { clock.now })

        for index in 0...500 {
            store.setEnabled(true, for: "post-\(index)")
            clock.now.addTimeInterval(1)
        }

        #expect(!store.isEnabled(for: "post-0"))
        #expect(store.isEnabled(for: "post-500"))
    }

    @Test func insightPreferencesArePerScanAndSeparateFromExplorePosts() throws {
        let suite = "InsightAudioBoostPreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let insightStore = InsightAudioBoostPreferenceStore(defaults: defaults)
        let exploreStore = ExploreAudioBoostPreferenceStore(defaults: defaults)

        insightStore.setEnabled(true, for: "scan-cardinal")

        #expect(insightStore.isEnabled(for: "scan-cardinal"))
        #expect(!insightStore.isEnabled(for: "scan-frog"))
        #expect(!exploreStore.isEnabled(for: "scan-cardinal"))
    }

    @Test func insightBoostRequiresPersistedCompletedStandaloneAudio() {
        #expect(InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: true,
            isProcessing: false,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: false,
            isProcessing: false,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: true,
            isProcessing: true,
            hasStandaloneAudio: true
        ))
        #expect(!InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: true,
            isProcessing: false,
            hasStandaloneAudio: false
        ))
    }
}
