import Foundation

enum AudioBoostPillState: Equatable {
    case boost
    case boosting
    case reverting
    case boosted

    static func resolve(
        isBoostEnabled: Bool,
        isPreparingBoost: Bool = false,
        isRevertingBoost: Bool = false,
        isBoostedAudioReady: Bool,
        hasToggleAction: Bool
    ) -> Self? {
        guard hasToggleAction else { return nil }
        if isBoostEnabled, isPreparingBoost { return .boosting }
        if !isBoostEnabled, isRevertingBoost { return .reverting }
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

enum AudioPlaybackControlPolicy {
    static let autoHideDelayNanoseconds: UInt64 = 1_000_000_000
    static let unexpectedStopGraceNanoseconds: UInt64 = 150_000_000

    static func shouldAutoHide(isPlaying: Bool, isSeeking: Bool) -> Bool {
        isPlaying && !isSeeking
    }

    static func shouldPresent(isVisible: Bool, isSeeking: Bool) -> Bool {
        isVisible && !isSeeking
    }

    static func shouldDisable(
        isHardwareDisabled: Bool,
        isPreparingSource: Bool,
        isPlaying: Bool
    ) -> Bool {
        isHardwareDisabled || (isPreparingSource && !isPlaying)
    }
}

enum AudioPlaybackFailurePolicy {
    static func recoveryTime(
        currentTime: TimeInterval,
        duration: TimeInterval,
        storedProgress: Double
    ) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        let clampedProgress = min(1, max(0, storedProgress))
        if clampedProgress > 0, clampedProgress < 1 {
            return clampedProgress * duration
        }
        guard currentTime.isFinite else { return 0 }
        return min(duration, max(0, currentTime))
    }
}

enum AudioSourceHandoffPolicy {
    static func shouldStageReplacement(
        isPlaybackActive: Bool,
        playerIsPlaying: Bool
    ) -> Bool {
        isPlaybackActive || playerIsPlaying
    }
}

enum AudioPlaybackTimeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}
