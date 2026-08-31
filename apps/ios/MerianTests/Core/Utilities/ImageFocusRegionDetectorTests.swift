import CoreGraphics
import Foundation
import Testing

@testable import Merian

@Suite("Image focus region resolver")
struct ImageFocusRegionDetectorTests {
    @Test func convertsVisionCoordinatesAndPadsAcceptedSubject() throws {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.3),
                confidence: 0.9
            )
        ])
        let region = try #require(resolution.region)

        #expect(abs(region.x - 0.152) < 0.0001)
        #expect(abs(region.y - 0.564) < 0.0001)
        #expect(abs(region.width - 0.496) < 0.0001)
        #expect(abs(region.height - 0.372) < 0.0001)
        #expect(region.source == .visionObjectness)
    }

    @Test func clampsPaddingAtImageBounds() throws {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0, y: 0.45, width: 0.35, height: 0.35),
                confidence: 0.9
            )
        ])
        let region = try #require(resolution.region)

        #expect(region.x == 0)
        #expect(region.y >= 0)
        #expect(region.x + region.width <= 1)
        #expect(region.y + region.height <= 1)
    }

    @Test func rejectsLowConfidenceTinyAndNearFullImageCandidates() {
        #expect(ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                confidence: 0.49
            )
        ]) == .lowConfidence)

        #expect(ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.05, height: 0.05),
                confidence: 0.9
            )
        ]) == .areaRejected)

        #expect(ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                confidence: 0.9
            )
        ]) == .areaRejected)
    }

    @Test func rejectsAmbiguousSeparatedSubjects() {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.08, y: 0.35, width: 0.3, height: 0.3),
                confidence: 0.91
            ),
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.62, y: 0.35, width: 0.3, height: 0.3),
                confidence: 0.86
            )
        ])

        #expect(resolution == .ambiguous)
    }

    @Test func centralCandidateWinsCloseOverlappingTie() throws {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.24, y: 0.28, width: 0.4, height: 0.4),
                confidence: 0.92
            ),
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                confidence: 0.89
            )
        ])
        let region = try #require(resolution.region)

        #expect(abs(region.x - 0.252) < 0.0001)
    }

    @Test func rejectsInvalidGeometry() {
        let resolution = ImageFocusRegionResolver.resolve(candidates: [
            ImageFocusRegionCandidate(
                boundingBox: CGRect(x: -0.1, y: 0.2, width: 0.4, height: 0.4),
                confidence: 0.9
            )
        ])

        #expect(resolution == .invalidGeometry)
    }
}
