import CoreGraphics
import Foundation

struct CaptureScanStillPreparationRequest: Sendable {
    let captureData: Data
    let composingCenter: CGFloat
    let isProActive: Bool
}

struct PreparedCaptureScanStill: Sendable {
    let inferenceData: Data
    let displayData: Data
    let previewCGImage: SendableCGImage
    let focusRegion: NormalizedImageFocusRegion?

    init(
        inferenceData: Data,
        displayData: Data,
        previewCGImage: SendableCGImage,
        focusRegion: NormalizedImageFocusRegion? = nil
    ) {
        self.inferenceData = inferenceData
        self.displayData = displayData
        self.previewCGImage = previewCGImage
        self.focusRegion = focusRegion
    }
}

struct CaptureScanVideoPreparationRequest: Sendable {
    let videoURL: URL
    let duration: TimeInterval
    let composingCenter: CGFloat
    let isProActive: Bool
}

enum CaptureScanVideoFrameSamplingPolicy {
    nonisolated static func sampleOffsets(
        duration: TimeInterval,
        sampleCount: Int
    ) -> [TimeInterval] {
        guard sampleCount > 0 else { return [] }

        let resolvedDuration = max(duration, 0.1)
        let normalizedPositions: [Double]
        if sampleCount == 1 {
            normalizedPositions = [0.5]
        } else {
            let step = 0.8 / Double(sampleCount - 1)
            normalizedPositions = (0..<sampleCount).map {
                0.1 + Double($0) * step
            }
        }

        return normalizedPositions.map {
            min(
                max(resolvedDuration * $0, 0.05),
                max(resolvedDuration - 0.05, 0.05)
            )
        }
    }
}

struct PreparedCaptureScanVideoPlayback: Sendable {
    let fileURL: URL
    let isCompressed: Bool
    let originalBytes: Int
    let playbackBytes: Int
    let preparationDuration: TimeInterval

    var sourceDescription: String {
        isCompressed ? "compressed" : "original"
    }

    var compressionRatio: Double {
        guard originalBytes > 0 else { return 1.0 }
        return Double(playbackBytes) / Double(originalBytes)
    }
}

struct PreparedCaptureScanVideo: Sendable {
    let sampledFrames: [PreparedCaptureScanStill]
    let audioFilePath: String?
    let playback: PreparedCaptureScanVideoPlayback
}
