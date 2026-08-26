import Foundation
import SwiftUI

enum ExploreVideoMutePreference {
    static let key = "MerianExplorePublicVideoMuted"

    @MainActor
    static func resetToMuted(
        defaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) {
        let eventSender = eventSender ?? AppDIContainer.shared.appEventPublisher
        defaults.set(true, forKey: key)
        eventSender.send(.exploreVideoMutePreferenceReset)
    }
}

struct ExploreVideoPlaybackOverlayState: Equatable {
    enum Event: Equatable {
        case autoplayStarted
        case playerBecamePlaying
        case playbackStarted
        case playbackPaused
        case playbackTemporarilyPaused
        case playbackWaiting
        case playbackUnavailable
        case playbackInterrupted
        case recoveryRebuildCompleted
        case revealControls
        case controlFadeCompleted
    }

    private(set) var isPlaying: Bool
    private(set) var showsPlaybackControl: Bool
    private(set) var needsPlayerRebuildForRecovery: Bool
    private(set) var isAutoplayControlSuppressed: Bool

    init(
        isPlaying: Bool = false,
        showsPlaybackControl: Bool = true,
        needsPlayerRebuildForRecovery: Bool = false,
        isAutoplayControlSuppressed: Bool = false
    ) {
        self.isPlaying = isPlaying
        self.showsPlaybackControl = showsPlaybackControl
        self.needsPlayerRebuildForRecovery = needsPlayerRebuildForRecovery
        self.isAutoplayControlSuppressed = isAutoplayControlSuppressed
    }

    mutating func reduce(_ event: Event) {
        switch event {
        case .autoplayStarted:
            isPlaying = true
            showsPlaybackControl = false
            needsPlayerRebuildForRecovery = false
            isAutoplayControlSuppressed = true
        case .playerBecamePlaying:
            isPlaying = true
            needsPlayerRebuildForRecovery = false
            if isAutoplayControlSuppressed {
                showsPlaybackControl = false
            }
        case .playbackStarted:
            isPlaying = true
            showsPlaybackControl = true
            needsPlayerRebuildForRecovery = false
            isAutoplayControlSuppressed = false
        case .playbackPaused:
            isPlaying = false
            showsPlaybackControl = true
            isAutoplayControlSuppressed = false
        case .playbackTemporarilyPaused:
            break
        case .playbackWaiting:
            if !isPlaying {
                showsPlaybackControl = true
                isAutoplayControlSuppressed = false
            }
        case .playbackUnavailable:
            isPlaying = false
            showsPlaybackControl = true
            needsPlayerRebuildForRecovery = false
            isAutoplayControlSuppressed = false
        case .playbackInterrupted:
            isPlaying = false
            showsPlaybackControl = true
            needsPlayerRebuildForRecovery = true
            isAutoplayControlSuppressed = false
        case .recoveryRebuildCompleted:
            needsPlayerRebuildForRecovery = false
            showsPlaybackControl = true
            isAutoplayControlSuppressed = false
        case .revealControls:
            showsPlaybackControl = true
            isAutoplayControlSuppressed = false
        case .controlFadeCompleted:
            showsPlaybackControl = !isPlaying || needsPlayerRebuildForRecovery
        }
    }
}

enum ExploreMediaInteractionPolicy {
    static let centerPlaybackHitSize: CGFloat = 96

    static func usesCenterPlaybackZone(
        surface: ExploreVideoPlaybackSurface,
        mediaKind: ExploreMediaKind,
        hasNavigationAction: Bool
    ) -> Bool {
        guard hasNavigationAction else { return false }
        guard mediaKind == .video || mediaKind == .audio else { return false }
        if case .feed = surface { return true }
        return false
    }
}

enum ExploreAudioBoostPillState: Equatable {
    case boost
    case boosting
    case reverting
    case boosted

    static func resolve(
        surface: ExploreVideoPlaybackSurface,
        mediaKind: ExploreMediaKind,
        isBoostEnabled: Bool,
        isPreparingBoost: Bool = false,
        isRevertingBoost: Bool = false,
        isBoostedAudioReady: Bool,
        hasToggleAction: Bool
    ) -> Self? {
        guard surface == .feed || surface == .detail,
              mediaKind == .audio,
              hasToggleAction else { return nil }
        if isBoostEnabled && isPreparingBoost { return .boosting }
        if !isBoostEnabled && isRevertingBoost { return .reverting }
        return isBoostEnabled && isBoostedAudioReady ? .boosted : .boost
    }

    var title: String {
        switch self {
        case .boost: "Boost audio"
        case .boosting: "Boosting…"
        case .reverting: "Reverting…"
        case .boosted: "Boosted audio"
        }
    }

    var systemImage: String? {
        self == .boost ? "chevron.right" : nil
    }

    var accessibilityLabel: String {
        switch self {
        case .boost: "Boost audio"
        case .boosting: "Boosting audio"
        case .reverting: "Reverting audio boost"
        case .boosted: "Turn off audio boost"
        }
    }
}

struct ExploreVideoPlaybackResumeIntentState: Equatable {
    private(set) var shouldResumeAfterSystemInterruption = false

    mutating func markSystemInterruption(shouldResume: Bool) {
        shouldResumeAfterSystemInterruption = shouldResumeAfterSystemInterruption || shouldResume
    }

    mutating func consumeSystemResumeIntent() -> Bool {
        let shouldResume = shouldResumeAfterSystemInterruption
        shouldResumeAfterSystemInterruption = false
        return shouldResume
    }

    mutating func clear() {
        shouldResumeAfterSystemInterruption = false
    }
}
