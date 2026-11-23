import CoreGraphics
import Testing

@testable import Merian

@Suite("Source-bound photo selection geometry")
struct CapturePhotoSelectionGeometryTests {
    @Test(arguments: [0, 1, 2, 3])
    func asymmetricSourceSelectionRotatesWithPhoto(turns: Int) throws {
        let geometry = make(turns: turns)
        let source = CGRect(x: 0.25, y: 0.375, width: 0.25, height: 0.125)
        let expected = [CGRect(x: 50, y: 50, width: 50, height: 50),
                        CGRect(x: 100, y: 50, width: 50, height: 50),
                        CGRect(x: 100, y: 100, width: 50, height: 50),
                        CGRect(x: 50, y: 100, width: 50, height: 50)]
        let viewport = try #require(geometry.viewportRect(for: source))
        #expect(viewport == expected[turns])
        #expect(geometry.sourceRect(for: viewport) == source)
    }

    @Test func viewportResizePreservesSourceAndSubmittedRegion() throws {
        let source = CGRect(x: 0.4, y: 0.45, width: 0.2, height: 0.1)
        let first = make(size: 200, scale: 2, offset: .init(width: 20, height: -10))
        let resized = make(size: 400, scale: 2, offset: .init(width: 40, height: -20))
        let rect = try #require(first.viewportRect(for: source))
        expectNear(rect, CGRect(x: 80, y: 50, width: 80, height: 80))
        let normalized = try #require(first.finalCropRect(for: source))
        expectNear(normalized, CGRect(x: 0.4, y: 0.25, width: 0.4, height: 0.4))
        expectNear(try #require(resized.finalCropRect(for: source)), normalized)
        let resizedViewport = try #require(resized.viewportRect(for: source))
        expectNear(try #require(resized.sourceRect(for: resizedViewport)), source)
    }

    @Test func cropExclusionClearsInsteadOfClippingEvidence() throws {
        let source = CGRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2)
        #expect(make().finalCropRect(for: source) != nil)
        let panned = make(offset: .init(width: 100, height: 0))
        // The overlay may move outside the viewport during the gesture, but
        // gesture-end validation must refuse a partially excluded subject.
        #expect(try #require(panned.viewportRect(for: source)).maxX > 200)
        #expect(panned.finalCropRect(for: source) == nil)
    }

    @Test func immediateFallbackAndRetapKeepSizeInsideViewport() throws {
        let geometry = make()
        let initial = try #require(geometry.selection(at: .init(x: 100, y: 100), existing: nil, candidates: []))
        expectNear(try #require(geometry.viewportRect(for: initial)), CGRect(x: 60, y: 60, width: 80, height: 80))
        let moved = try #require(geometry.selection(at: .init(x: 195, y: 5), existing: initial, candidates: []))
        expectNear(try #require(geometry.viewportRect(for: moved)), CGRect(x: 120, y: 0, width: 80, height: 80))
    }

    @Test func candidateMustContainTapBeVisibleAndMeetInteractiveMinimum() throws {
        let geometry = CapturePhotoSelectionGeometry(sourceSize: .init(width: 400, height: 400),
            viewportSize: 400, scale: 1, offset: .zero, quarterTurns: 0)
        let outer = CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7)
        let inner = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let tiny = CGRect(x: 0.35, y: 0.35, width: 0.02, height: 0.02)
        let invalid = CGRect(x: -0.1, y: 0, width: 0.8, height: 0.8)
        let selected = try #require(geometry.selection(at: .init(x: 145, y: 145), existing: nil,
                                                      candidates: [invalid, outer, tiny, inner]))
        expectNear(selected, inner)
    }

    @Test(arguments: CapturePhotoSelectionGeometry.Corner.allCases)
    func cornerCannotCrossItsFixedOpposite(corner: CapturePhotoSelectionGeometry.Corner) throws {
        let geometry = make()
        let original = try #require(geometry.sourceRect(for: CGRect(x: 50, y: 50, width: 100, height: 100)))
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let moved = try #require(geometry.resized(original, corner: corner,
            to: .init(x: left ? 190 : 10, y: top ? 190 : 10)))
        let rect = try #require(geometry.viewportRect(for: moved))
        expectNear(rect, CGRect(x: left ? 86 : 50, y: top ? 86 : 50, width: 64, height: 64))
        #expect(geometry.finalCropRect(for: moved) != nil)
    }

    @Test func invalidGeometryNeverBecomesSelection() {
        let geometry = make()
        #expect(geometry.viewportRect(for: .init(x: CGFloat.nan, y: 0, width: 0.5, height: 0.5)) == nil)
        #expect(geometry.viewportRect(for: .init(x: 0, y: 0, width: -0.5, height: 0.5)) == nil)
        #expect(geometry.sourceRect(for: .init(x: 0, y: 0, width: CGFloat.infinity, height: 50)) == nil)
        #expect(geometry.selection(at: .init(x: CGFloat.nan, y: 50), existing: nil, candidates: []) == nil)
        #expect(make(size: 0).selection(at: .zero, existing: nil, candidates: []) == nil)
    }

    @Test func fittedSourceCoordinatesRejectAReframedViewport() {
        let selection = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        for (scale, offset, turns) in [(CGFloat(2), CGSize.zero, 0), (1, CGSize(width: 1, height: 0), 0), (1, .zero, 1)] {
            let geometry = CapturePhotoSelectionGeometry(sourceSize: .init(width: 400, height: 200),
                viewportSize: 200, scale: scale, offset: offset, quarterTurns: turns, fitsFullAspect: true)
            #expect(!geometry.isValid)
            #expect(geometry.finalCropRect(for: selection) == nil)
        }
    }

    @Test func smallerViewportKeepsTheOppositeCornerAndBounds() throws {
        let geometry = make(size: 80)
        let original = try #require(geometry.sourceRect(for: CGRect(x: 10, y: 10, width: 20, height: 20)))
        let resized = try #require(geometry.resized(original, corner: .topLeft, to: .init(x: 25, y: 25)))
        expectNear(try #require(geometry.viewportRect(for: resized)), CGRect(x: 0, y: 0, width: 30, height: 30))
    }

    private func make(size: CGFloat = 200, scale: CGFloat = 1, offset: CGSize = .zero,
                      turns: Int = 0) -> CapturePhotoSelectionGeometry {
        .init(sourceSize: .init(width: 100, height: 200), viewportSize: size,
              scale: scale, offset: offset, quarterTurns: turns)
    }

    private func expectNear(_ actual: CGRect, _ expected: CGRect) {
        #expect(abs(actual.minX - expected.minX) < 0.000001)
        #expect(abs(actual.minY - expected.minY) < 0.000001)
        #expect(abs(actual.width - expected.width) < 0.000001)
        #expect(abs(actual.height - expected.height) < 0.000001)
    }
}
