@preconcurrency import AVFoundation
import Foundation

struct CameraZoomConfiguration: Equatable, Sendable {
    let maximumFactor: CGFloat
    let opticalStops: [CGFloat]
    let currentFactor: CGFloat
}

enum CameraSessionPolicy {
    static func zoomConfiguration(
        maximumAvailableFactor: CGFloat,
        switchOverFactors: [CGFloat],
        currentFactor: CGFloat
    ) -> CameraZoomConfiguration {
        let maximumFactor = min(maximumAvailableFactor, 15)
        let opticalStops = ([1] + switchOverFactors).filter {
            $0 <= maximumFactor
        }
        return CameraZoomConfiguration(
            maximumFactor: maximumFactor,
            opticalStops: opticalStops,
            currentFactor: currentFactor
        )
    }

    static func presentationZoomFactor(
        requestedFactor: CGFloat,
        maximumFactor: CGFloat
    ) -> CGFloat {
        min(max(requestedFactor, 1), maximumFactor)
    }

    static func hardwareZoomFactor(
        presentationFactor: CGFloat,
        minimumFactor: CGFloat,
        maximumFactor: CGFloat
    ) -> CGFloat {
        min(max(presentationFactor, minimumFactor), maximumFactor)
    }

    static func clampedFrameDuration(
        requestedDuration: CMTime,
        minimumDuration: CMTime?,
        maximumDuration: CMTime?
    ) -> CMTime {
        guard let minimumDuration, let maximumDuration else {
            return requestedDuration
        }
        if CMTimeCompare(requestedDuration, minimumDuration) < 0 {
            return minimumDuration
        }
        if CMTimeCompare(requestedDuration, maximumDuration) > 0 {
            return maximumDuration
        }
        return requestedDuration
    }

    static func shouldSetMaximumDurationFirst(
        targetDuration: CMTime,
        currentMinimumDuration: CMTime
    ) -> Bool {
        CMTimeCompare(targetDuration, currentMinimumDuration) > 0
    }
}
