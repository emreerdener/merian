import CoreGraphics
import Foundation

/// Capture telemetry façade; Core owns image work and its drain boundary.
enum ImageFocusRegionDetector {
    static let timeout = ImageFocusEngine.timeout

    static func detect(in imageData: Data) async -> NormalizedImageFocusRegion? {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let workerResult = await ImageFocusEngine.detect(in: imageData)

        let resolution: ImageFocusRegionResolution?
        let outcome: String
        switch workerResult {
        case .candidates(let candidates):
            let resolved = ImageFocusRegionResolver.resolve(candidates: candidates)
            resolution = resolved
            outcome = resolved.telemetryOutcome
        case .noCandidates:
            resolution = .noCandidates
            outcome = ImageFocusRegionResolution.noCandidates.telemetryOutcome
        case .failed:
            resolution = nil
            outcome = "error"
        case .timedOut:
            resolution = nil
            outcome = "timeout"
        case .cancelled:
            resolution = nil
            outcome = "cancelled"
        }

        let durationMilliseconds = max(0, Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000))
        let region = resolution?.region
        let regionAreaBucket = region.map { areaBucket(for: $0.width * $0.height) }
        MerianLog.general.debug(
            "Image focus detection outcome=\(outcome, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public) areaBucket=\(regionAreaBucket ?? "none", privacy: .public)"
        )
        AppTelemetry.trackImageFocusDetection(
            durationMilliseconds: durationMilliseconds,
            outcome: outcome,
            areaBucket: regionAreaBucket
        )
        return region
    }

    private static func areaBucket(for area: CGFloat) -> String {
        if area < 0.15 { return "small" }
        if area < 0.40 { return "medium" }
        return "large"
    }
}
