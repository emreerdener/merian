import CoreGraphics
import Foundation

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
