import CoreGraphics
import Foundation
import Vision

struct ImageFocusRegionCandidate: Sendable, Equatable {
    /// Vision-normalized bounds using Vision's lower-left origin.
    let boundingBox: CGRect
    let confidence: Float
}

enum ImageFocusRegionResolution: Sendable, Equatable {
    case accepted(NormalizedImageFocusRegion)
    case noCandidates
    case lowConfidence
    case invalidGeometry
    case areaRejected
    case ambiguous

    var region: NormalizedImageFocusRegion? {
        guard case .accepted(let region) = self else { return nil }
        return region
    }

    var telemetryOutcome: String {
        switch self {
        case .accepted:
            return "accepted"
        case .noCandidates:
            return "no_subject"
        case .lowConfidence:
            return "low_confidence"
        case .invalidGeometry:
            return "invalid_geometry"
        case .areaRejected:
            return "area_rejected"
        case .ambiguous:
            return "ambiguous"
        }
    }
}

enum ImageFocusRegionResolver {
    static let minimumConfidence: Float = 0.50
    static let centralTieBreakConfidenceDelta: Float = 0.05
    static let ambiguityConfidenceDelta: Float = 0.08
    static let ambiguityMaximumIntersectionOverUnion: CGFloat = 0.25
    static let subjectPaddingFraction: CGFloat = 0.12
    static let minimumAreaFraction: CGFloat = 0.03
    static let maximumAreaFraction: CGFloat = 0.70

    static func resolve(candidates: [ImageFocusRegionCandidate]) -> ImageFocusRegionResolution {
        guard !candidates.isEmpty else { return .noCandidates }

        let geometricallyValid = candidates.filter { candidate in
            candidate.confidence.isFinite && isValidVisionRect(candidate.boundingBox)
        }
        guard !geometricallyValid.isEmpty else { return .invalidGeometry }

        let eligible = geometricallyValid.filter { $0.confidence >= minimumConfidence }
        guard !eligible.isEmpty else { return .lowConfidence }

        let highestConfidence = eligible.map(\.confidence).max() ?? minimumConfidence
        let nearHighest = eligible.filter {
            highestConfidence - $0.confidence <= centralTieBreakConfidenceDelta
        }
        let selected = nearHighest.min { lhs, rhs in
            distanceFromCenter(visionRect: lhs.boundingBox) < distanceFromCenter(visionRect: rhs.boundingBox)
        } ?? eligible[0]

        let selectedTopLeftRect = topLeftRect(fromVisionRect: selected.boundingBox)
        let paddedRect = paddedAndClamped(selectedTopLeftRect)
        let area = paddedRect.width * paddedRect.height
        guard area >= minimumAreaFraction, area <= maximumAreaFraction else {
            return .areaRejected
        }

        let hasAmbiguousRunnerUp = eligible.contains { candidate in
            guard candidate != selected else { return false }
            guard selected.confidence - candidate.confidence <= ambiguityConfidenceDelta else {
                return false
            }
            let candidateRect = topLeftRect(fromVisionRect: candidate.boundingBox)
            return intersectionOverUnion(selectedTopLeftRect, candidateRect)
                < ambiguityMaximumIntersectionOverUnion
        }
        guard !hasAmbiguousRunnerUp else { return .ambiguous }

        return .accepted(NormalizedImageFocusRegion(
            x: paddedRect.minX,
            y: paddedRect.minY,
            width: paddedRect.width,
            height: paddedRect.height
        ))
    }

    static func topLeftRect(fromVisionRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: 1 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func paddedAndClamped(_ rect: CGRect) -> CGRect {
        let horizontalPadding = rect.width * subjectPaddingFraction
        let verticalPadding = rect.height * subjectPaddingFraction
        let padded = rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        return padded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private static func isValidVisionRect(_ rect: CGRect) -> Bool {
        let values = [rect.minX, rect.minY, rect.width, rect.height, rect.maxX, rect.maxY]
        guard values.allSatisfy(\.isFinite), rect.width > 0, rect.height > 0 else { return false }
        return rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= 1 && rect.maxY <= 1
    }

    private static func distanceFromCenter(visionRect: CGRect) -> CGFloat {
        let dx = visionRect.midX - 0.5
        let dy = visionRect.midY - 0.5
        return dx * dx + dy * dy
    }
}

private enum ImageFocusVisionWorkerResult: Sendable {
    case candidates([ImageFocusRegionCandidate])
    case noCandidates
    case failed
    case timedOut
    case cancelled
}

private final class ImageFocusVisionRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ImageFocusVisionWorkerResult, Never>?
    private var request: VNGenerateObjectnessBasedSaliencyImageRequest?
    private var isResolved = false

    func start(
        continuation: CheckedContinuation<ImageFocusVisionWorkerResult, Never>,
        imageData: Data,
        timeout: TimeInterval
    ) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            continuation.resume(returning: .cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = autoreleasepool {
                guard let cgImage = ImageDownsampler.downsample(data: imageData, maxSize: 512) else {
                    return ImageFocusVisionWorkerResult.failed
                }

                let request = VNGenerateObjectnessBasedSaliencyImageRequest()
                request.revision = VNGenerateObjectnessBasedSaliencyImageRequestRevision2
                guard install(request: request) else { return .cancelled }

                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                    try handler.perform([request])
                    guard let salientObjects = request.results?.first?.salientObjects,
                          !salientObjects.isEmpty else {
                        return .noCandidates
                    }
                    return .candidates(salientObjects.map {
                        ImageFocusRegionCandidate(
                            boundingBox: $0.boundingBox,
                            confidence: $0.confidence
                        )
                    })
                } catch {
                    return .failed
                }
            }
            resolve(result)
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [self] in
            cancel(with: .timedOut)
        }
    }

    func cancel(with result: ImageFocusVisionWorkerResult) {
        let requestToCancel: VNRequest?
        let continuationToResume: CheckedContinuation<ImageFocusVisionWorkerResult, Never>?

        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        requestToCancel = request
        request = nil
        continuationToResume = continuation
        continuation = nil
        lock.unlock()

        requestToCancel?.cancel()
        continuationToResume?.resume(returning: result)
    }

    private func install(request: VNGenerateObjectnessBasedSaliencyImageRequest) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isResolved else {
            request.cancel()
            return false
        }
        self.request = request
        return true
    }

    private func resolve(_ result: ImageFocusVisionWorkerResult) {
        let continuationToResume: CheckedContinuation<ImageFocusVisionWorkerResult, Never>?

        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        request = nil
        continuationToResume = continuation
        continuation = nil
        lock.unlock()

        continuationToResume?.resume(returning: result)
    }
}

enum ImageFocusRegionDetector {
    static let timeout: TimeInterval = 0.300

    static func detect(in imageData: Data) async -> NormalizedImageFocusRegion? {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let state = ImageFocusVisionRequestState()
        let workerResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.start(
                    continuation: continuation,
                    imageData: imageData,
                    timeout: timeout
                )
            }
        } onCancel: {
            state.cancel(with: .cancelled)
        }

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
