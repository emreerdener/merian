import AVFoundation
import CoreGraphics
import Foundation

enum MediaPlaybackFeedbackEvent: String, Sendable {
    case audioPause = "audio.pause"
    case audioPlay = "audio.play"
    case audioPlayFailed = "audio.play.failed"
    case audioSeekTap = "audio.seek.tap"
    case audioSeekBegin = "audio.seek.begin"
    case audioSeekCommit = "audio.seek.commit"
    case audioSeekAccessibility = "audio.seek.accessibility"
    case audioBoostFailed = "audioBoost.failed"
    case fullscreenMuteOn = "fullscreen.mute.on"
    case fullscreenMuteOff = "fullscreen.mute.off"
    case fullscreenUnmute = "fullscreen.unmute"
    case fullscreenSelection = "fullscreen.selection"
    case fullscreenLoop = "fullscreen.loop"
    case fullscreenPause = "fullscreen.pause"
    case fullscreenPlay = "fullscreen.play"
    case fullscreenAutoplay = "fullscreen.autoplay"
}

@MainActor
struct MediaPlaybackDependencies {
    let feedbackNamespace: String
    let activatePlaybackAudio: @MainActor (_ source: String) async -> Bool
    let activateAudioPlayerSession: @MainActor () throws -> Void
    let acquireAudioSource: @MainActor (
        _ source: String
    ) async throws -> AudioSourceLease
    let prepareAudioBoost: @MainActor (
        _ source: String
    ) async throws -> AudioBoostResult
    let invalidateAudioBoost: @MainActor (_ source: String) async -> Void
    let trackAudioBoost: @MainActor (
        _ event: String,
        _ gainBand: String?
    ) -> Void
    let selectionFeedback: @MainActor (_ source: String?) -> Void
    let lightImpactFeedback: @MainActor (
        _ intensity: CGFloat?,
        _ source: String?
    ) -> Void
    let mediumPulseFeedback: @MainActor (_ source: String?) -> Void
    let errorFeedback: @MainActor (_ source: String?) -> Void

    init(
        feedbackNamespace: String = "media",
        activatePlaybackAudio: @escaping @MainActor (
            _ source: String
        ) async -> Bool = { _ in true },
        activateAudioPlayerSession: @escaping @MainActor () throws -> Void = {},
        acquireAudioSource: @escaping @MainActor (
            _ source: String
        ) async throws -> AudioSourceLease = { _ in
            throw CocoaError(.fileNoSuchFile)
        },
        prepareAudioBoost: @escaping @MainActor (
            _ source: String
        ) async throws -> AudioBoostResult = { _ in
            throw CocoaError(.fileReadCorruptFile)
        },
        invalidateAudioBoost: @escaping @MainActor (
            _ source: String
        ) async -> Void = { _ in },
        trackAudioBoost: @escaping @MainActor (
            _ event: String,
            _ gainBand: String?
        ) -> Void = { _, _ in },
        selectionFeedback: @escaping @MainActor (
            _ source: String?
        ) -> Void = { _ in },
        lightImpactFeedback: @escaping @MainActor (
            _ intensity: CGFloat?,
            _ source: String?
        ) -> Void = { _, _ in },
        mediumPulseFeedback: @escaping @MainActor (
            _ source: String?
        ) -> Void = { _ in },
        errorFeedback: @escaping @MainActor (
            _ source: String?
        ) -> Void = { _ in }
    ) {
        self.feedbackNamespace = feedbackNamespace
        self.activatePlaybackAudio = activatePlaybackAudio
        self.activateAudioPlayerSession = activateAudioPlayerSession
        self.acquireAudioSource = acquireAudioSource
        self.prepareAudioBoost = prepareAudioBoost
        self.invalidateAudioBoost = invalidateAudioBoost
        self.trackAudioBoost = trackAudioBoost
        self.selectionFeedback = selectionFeedback
        self.lightImpactFeedback = lightImpactFeedback
        self.mediumPulseFeedback = mediumPulseFeedback
        self.errorFeedback = errorFeedback
    }

    static var live: Self {
        let hapticManager = HapticManager.shared
        return Self(
            activatePlaybackAudio: { source in
                await MediaPlaybackAudioSession.activate(source: source)
            },
            activateAudioPlayerSession: {
                try AVAudioSession.sharedInstance().setActive(true)
            },
            acquireAudioSource: { source in
                try await AudioBoostProcessor.shared.acquireSource(source)
            },
            prepareAudioBoost: { source in
                try await AudioBoostProcessor.shared.prepare(source: source)
            },
            invalidateAudioBoost: { source in
                await AudioBoostProcessor.shared.invalidate(source: source)
            },
            selectionFeedback: { source in
                hapticManager.triggerSelectionPulse(source: source)
            },
            lightImpactFeedback: { intensity, source in
                hapticManager.triggerLightImpact(
                    intensity: intensity,
                    source: source
                )
            },
            mediumPulseFeedback: { source in
                hapticManager.triggerMediumPulse(source: source)
            },
            errorFeedback: { source in
                hapticManager.triggerErrorThump(source: source)
            }
        )
    }

    func configuredForFeature(
        feedbackNamespace: String,
        using tracker: @escaping @MainActor (
            _ event: String,
            _ gainBand: String?
        ) -> Void
    ) -> Self {
        Self(
            feedbackNamespace: feedbackNamespace,
            activatePlaybackAudio: activatePlaybackAudio,
            activateAudioPlayerSession: activateAudioPlayerSession,
            acquireAudioSource: acquireAudioSource,
            prepareAudioBoost: prepareAudioBoost,
            invalidateAudioBoost: invalidateAudioBoost,
            trackAudioBoost: tracker,
            selectionFeedback: selectionFeedback,
            lightImpactFeedback: lightImpactFeedback,
            mediumPulseFeedback: mediumPulseFeedback,
            errorFeedback: errorFeedback
        )
    }

    func feedbackIdentifier(_ event: MediaPlaybackFeedbackEvent) -> String {
        "\(feedbackNamespace).\(event.rawValue)"
    }
}
