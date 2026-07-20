import CoreGraphics
import Foundation

enum AudioSpectrogramSeekingMode: Equatable {
    case disabled
    case fullSpectrogram
    case playmarkerOnly
}

enum AudioSeekAdjustment: Equatable {
    case backward
    case forward
}

struct AudioSpectrogramSeekingPolicy {
    static let playmarkerHitWidth: CGFloat = 44
    static let accessibilityStepSeconds: TimeInterval = 5

    static func normalizedProgress(locationX: CGFloat, width: CGFloat) -> Double {
        guard width.isFinite, width > 0, locationX.isFinite else { return 0 }
        return min(1, max(0, Double(locationX / width)))
    }

    static func seconds(progress: Double, duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, clampedProgress(progress) * duration)
    }

    static func normalizedProgress(
        currentTime: TimeInterval,
        duration: TimeInterval,
        fallback: Double
    ) -> Double {
        guard currentTime.isFinite, duration.isFinite, duration > 0 else {
            return clampedProgress(fallback)
        }
        return clampedProgress(currentTime / duration)
    }

    static func displayedProgress(
        storedProgress: Double,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        playerIsPlaying: Bool,
        isSeeking: Bool
    ) -> Double {
        guard isPlaying, playerIsPlaying, !isSeeking else {
            return clampedProgress(storedProgress)
        }
        return normalizedProgress(
            currentTime: currentTime,
            duration: duration,
            fallback: storedProgress
        )
    }

    static func progress(
        after adjustment: AudioSeekAdjustment,
        currentProgress: Double,
        duration: TimeInterval,
        stepSeconds: TimeInterval = accessibilityStepSeconds
    ) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        let currentSeconds = seconds(progress: currentProgress, duration: duration)
        let delta = adjustment == .forward ? stepSeconds : -stepSeconds
        return min(1, max(0, (currentSeconds + delta) / duration))
    }

    static func playmarkerCenterX(progress: Double, width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        return min(width, max(0, width * CGFloat(clampedProgress(progress))))
    }

    static func playmarkerLeadingX(
        progress: Double,
        width: CGFloat,
        markerWidth: CGFloat = 2
    ) -> CGFloat {
        guard width.isFinite, width > 0, markerWidth.isFinite else { return 0 }
        let availableWidth = max(0, width - max(0, markerWidth))
        return availableWidth * CGFloat(clampedProgress(progress))
    }

    private static func clampedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }
}
