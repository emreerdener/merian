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
        #expect(ExploreAudioBoostProcessor.adaptiveGainDecibels(rmsDb: -50, peakDb: -30) == 18)
        #expect(ExploreAudioBoostProcessor.adaptiveGainDecibels(rmsDb: -30, peakDb: -4) == 3)
        #expect(ExploreAudioBoostProcessor.adaptiveGainDecibels(rmsDb: -12, peakDb: -0.5) == 0)
    }

    @Test func preparationFeedbackRequiresExplicitActionToken() {
        #expect(!ExploreAudioBoostFeedbackPolicy.shouldPresent(actionToken: nil))
        #expect(ExploreAudioBoostFeedbackPolicy.shouldPresent(actionToken: UUID()))
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
}
