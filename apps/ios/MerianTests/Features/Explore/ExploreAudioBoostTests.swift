import AVFoundation
import Combine
import Foundation
@testable import Merian
import Testing

@Suite("Explore Audio Boost Tests")
struct ExploreAudioBoostTests {
    @Test func detailZoomLayoutRejectsUnboundedAndInvalidFrameDimensions() {
        #expect(
            ExploreDetailZoomLayoutPolicy.resolvedSize(width: 320, height: .infinity)
                == CGSize(width: 320, height: 320)
        )
        #expect(
            ExploreDetailZoomLayoutPolicy.resolvedSize(width: 320, height: 280)
                == CGSize(width: 320, height: 280)
        )
        #expect(
            ExploreDetailZoomLayoutPolicy.resolvedSize(width: -.infinity, height: 280)
                == CGSize(width: 280, height: 280)
        )
        #expect(ExploreDetailZoomLayoutPolicy.resolvedSize(width: -.infinity, height: .nan) == nil)
    }

    @Test @MainActor func preferencesAreIndependentPerPost() throws {
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

    @Test @MainActor func preferenceChangesPublishTypedEventsOnce() throws {
        let suite = "ExploreAudioBoostNotificationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExploreAudioBoostPreferenceStore(defaults: defaults)
        let targetPostId = "notification-post-\(UUID().uuidString)"
        let eventPublisher = AppEventPublisher()
        var changes: [(String, Bool)] = []
        let cancellable = eventPublisher.publisher.sink { event in
            guard case .exploreAudioBoostPreferenceChanged(let postId, let enabled) = event,
                  postId == targetPostId else { return }
            changes.append((postId, enabled))
        }
        defer { cancellable.cancel() }

        store.setEnabled(true, for: targetPostId, eventSender: eventPublisher)
        store.setEnabled(true, for: targetPostId, eventSender: eventPublisher)
        store.setEnabled(false, for: targetPostId, eventSender: eventPublisher)

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
        #expect(!AudioBoostFeedbackPolicy.shouldPresent(actionToken: nil))
        #expect(AudioBoostFeedbackPolicy.shouldPresent(actionToken: UUID()))
    }

    @Test func feedBoostPillPresentsShortcutUntilBoostedAudioIsReady() {
        let unboosted = ExploreAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let preparing = ExploreAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let boosted = ExploreAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: true,
            isBoostedAudioReady: true,
            hasToggleAction: true
        )
        let boosting = ExploreAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: true,
            isPreparingBoost: true,
            isBoostedAudioReady: false,
            hasToggleAction: true
        )
        let reverting = ExploreAudioBoostPillState.resolve(
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

    @Test func exploreBoostPillIsLimitedToInteractiveFeedAndDetailAudio() {
        #expect(ExploreAudioBoostPillState.resolve(
            surface: .detail,
            mediaKind: .audio,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        ) == .boost)
        #expect(ExploreAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .video,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: true
        ) == nil)
        #expect(ExploreAudioBoostPillState.resolve(
            surface: .feed,
            mediaKind: .audio,
            isBoostEnabled: false,
            isBoostedAudioReady: false,
            hasToggleAction: false
        ) == nil)
    }

    @Test func exploreAudioPlayheadUsesLivePlayerTimeOnlyDuringPlayback() {
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: 0.2,
            currentTime: 7.5,
            duration: 15,
            isPlaying: true,
            playerIsPlaying: true,
            isSeeking: false
        ) == 0.5)
        #expect(AudioSpectrogramSeekingPolicy.displayedProgress(
            storedProgress: 0.2,
            currentTime: 7.5,
            duration: 15,
            isPlaying: true,
            playerIsPlaying: false,
            isSeeking: false
        ) == 0.2)
    }

    @Test func boostedAudioIsFullyReadableBeforePublication() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-boost-source-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let expectedFrameLength: AVAudioFramePosition = 4_800
        try Self.writeTestAudio(to: sourceURL, frameLength: AVAudioFrameCount(expectedFrameLength))

        let result = try await AudioBoostProcessor.shared.prepare(source: sourceURL.path)
        defer { try? FileManager.default.removeItem(at: result.url) }
        let rendered = try AVAudioFile(forReading: result.url)

        #expect(result.url.pathExtension == "caf")
        #expect(rendered.length == expectedFrameLength)
        var decodedFrameLength: AVAudioFramePosition = 0
        while decodedFrameLength < expectedFrameLength {
            let capacity = AVAudioFrameCount(min(expectedFrameLength - decodedFrameLength, 512))
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: rendered.processingFormat,
                frameCapacity: capacity
            ))
            let positionBeforeRead = rendered.framePosition
            try rendered.read(into: buffer)
            #expect(buffer.frameLength > 0)
            #expect(rendered.framePosition > positionBeforeRead)
            guard buffer.frameLength > 0, rendered.framePosition > positionBeforeRead else { break }
            decodedFrameLength += AVAudioFramePosition(buffer.frameLength)
        }
        #expect(decodedFrameLength == expectedFrameLength)
        await AudioBoostProcessor.shared.invalidate(source: sourceURL.path)
    }

    @Test @MainActor func returningToExploreFeedResetsVideoMutePreference() throws {
        let suite = "ExploreVideoMutePreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ExploreVideoMutePreference.key)

        ExploreVideoMutePreference.resetToMuted(defaults: defaults)

        #expect(defaults.bool(forKey: ExploreVideoMutePreference.key))
    }

    @Test @MainActor func preferencesExpireAfterOneHundredEightyDays() throws {
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

    @Test @MainActor func preferencesKeepOnlyFiveHundredMostRecentPosts() throws {
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

    private static func writeTestAudio(
        to url: URL,
        frameLength: AVAudioFrameCount
    ) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength),
              let samples = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frameLength
        for frame in 0..<Int(frameLength) {
            samples[frame] = Float(sin(2 * Double.pi * 880 * Double(frame) / format.sampleRate) * 0.1)
        }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
    }
}
