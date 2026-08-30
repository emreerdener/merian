import SwiftUI
import XCTest

@testable import Merian

final class CaptureShellPresentationPolicyTests: XCTestCase {
    func testGoalSwipeRequiresDominantHorizontalTranslation() {
        XCTAssertEqual(
            ActiveCaptureGoalSwipeDirection.resolve(
                horizontal: -80,
                vertical: 20
            ),
            .next
        )
        XCTAssertEqual(
            ActiveCaptureGoalSwipeDirection.resolve(
                horizontal: 80,
                vertical: 20
            ),
            .previous
        )
        XCTAssertNil(
            ActiveCaptureGoalSwipeDirection.resolve(
                horizontal: 36,
                vertical: 0
            )
        )
        XCTAssertNil(
            ActiveCaptureGoalSwipeDirection.resolve(
                horizontal: 80,
                vertical: 70
            )
        )
    }

    func testGoalExpansionOnlySurvivesVisibleVisualCapture() {
        XCTAssertEqual(
            CaptureGoalIndicatorExpansionState.expanded
                .preservingOnly(in: .visual),
            .expanded
        )
        XCTAssertEqual(
            CaptureGoalIndicatorExpansionState.expanded
                .preservingOnly(in: .audio),
            .collapsed
        )
        XCTAssertEqual(
            CaptureGoalIndicatorExpansionState.expanded
                .preservingOnly(whenVisible: false),
            .collapsed
        )
        XCTAssertEqual(
            CaptureGoalIndicatorExpansionState.collapsed.toggled,
            .expanded
        )
    }

    func testCompactGoalMarginPreservesMinimumSelectorGap() {
        XCTAssertEqual(
            CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                containerWidth: 390
            ),
            32
        )
        XCTAssertEqual(
            CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                containerWidth: 280
            ),
            0
        )
        XCTAssertEqual(
            CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                containerWidth: .infinity
            ),
            32
        )
    }

    func testArtworkRotationWrapsAndNormalizesNegativeIndices() {
        let artworks: [CaptureGoalArtwork] = [
            .bundledImage(name: "Bird"),
            .bundledImage(name: "Dog")
        ]

        XCTAssertEqual(
            CaptureGoalArtworkRotation.artwork(at: -1, in: artworks),
            artworks[1]
        )
        XCTAssertEqual(
            CaptureGoalArtworkRotation.nextIndex(after: 1, count: 2),
            0
        )
        XCTAssertEqual(
            CaptureGoalArtworkRotation.artwork(at: 4, in: []),
            .systemSymbol(name: "binoculars.fill")
        )
    }

    func testGoalVisibilityRequiresEveryPresentationCondition() {
        XCTAssertTrue(
            ActiveCaptureGoalPresentationPolicy.shouldShow(
                goalsEnabled: true,
                isUserVisible: true,
                isVisualMode: true,
                hasPresentation: true,
                stagedCaptureIsEmpty: true,
                isRefining: false,
                isVideoRecording: false
            )
        )
        XCTAssertFalse(
            ActiveCaptureGoalPresentationPolicy.shouldShow(
                goalsEnabled: true,
                isUserVisible: true,
                isVisualMode: true,
                hasPresentation: true,
                stagedCaptureIsEmpty: false,
                isRefining: false,
                isVideoRecording: false
            )
        )
        XCTAssertFalse(
            ActiveCaptureGoalPresentationPolicy.shouldShow(
                goalsEnabled: true,
                isUserVisible: true,
                isVisualMode: true,
                hasPresentation: true,
                stagedCaptureIsEmpty: true,
                isRefining: true,
                isVideoRecording: false
            )
        )
    }

    func testOptionalItemPresentationBindingClearsOnlyOnDismissal() {
        var item: Int? = 7
        let itemBinding = Binding(
            get: { item },
            set: { item = $0 }
        )
        let isPresented = CaptureWorkspacePresentationBindings.isPresented(
            by: itemBinding
        )

        XCTAssertTrue(isPresented.wrappedValue)
        isPresented.wrappedValue = true
        XCTAssertEqual(item, 7)
        isPresented.wrappedValue = false
        XCTAssertNil(item)
    }
}
