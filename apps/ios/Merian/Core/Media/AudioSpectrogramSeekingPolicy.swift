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
        return min(duration, max(0, progress.isFinite ? progress : 0) * duration)
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
        return min(width, max(0, width * CGFloat(progress.isFinite ? progress : 0)))
    }
}
