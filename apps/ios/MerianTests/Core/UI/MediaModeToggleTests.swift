import SwiftUI
import Testing
import UIKit

@testable import Merian

@MainActor
@Suite("Capture mode selector")
struct MediaModeToggleTests {
    @Test("Every capture mode has stable accessibility and symbol metadata")
    func captureModeMetadataIsStable() {
        let titles = CaptureMode.allCases.map(\.title)

        #expect(titles == ["Scan", "Record", "Describe"])
        #expect(Set(titles).count == CaptureMode.allCases.count)
        #expect(CaptureMode.allCases.map(\.symbolName) == [
            "viewfinder",
            "waveform",
            "text.bubble"
        ])
    }

    @Test("Every capture mode symbol resolves and is unique")
    func captureModeSymbolsAreAvailable() {
        let symbolNames = CaptureMode.allCases.map(\.symbolName)

        #expect(Set(symbolNames).count == CaptureMode.allCases.count)
        for symbolName in symbolNames {
            #expect(UIImage(systemName: symbolName) != nil)
        }
    }

    @Test("Selector uses compact tab-style proportions and high-contrast symbols")
    func selectorStyleIsCompactAndContrasting() {
        #expect(CaptureModeSelectorStyle.controlWidth == 200)
        #expect(CaptureModeSelectorStyle.controlHeight == 56)
        #expect(CaptureModeSelectorStyle.symbolPointSize == 24)
        #expect(CaptureModeSelectorStyle.describeContentClearance == 82)
        #expect(CaptureModeSelectorStyle.controlWidth <= 375 - 48)
        #expect(
            CaptureModeSelectorStyle.controlWidth / CGFloat(CaptureMode.allCases.count) >= 44
        )
        let horizontalSymbolPadding = (
            CaptureModeSelectorStyle.controlWidth / CGFloat(CaptureMode.allCases.count)
                - CaptureModeSelectorStyle.symbolPointSize
        ) / 2
        #expect(horizontalSymbolPadding >= 21)

        #expect(
            CaptureModeSelectorStyle.symbolColor(
                isSelected: true,
                colorScheme: .dark
            ).isEqual(UIColor.black)
        )
        #expect(
            CaptureModeSelectorStyle.symbolColor(
                isSelected: true,
                colorScheme: .light
            ).isEqual(UIColor.black)
        )
        #expect(
            CaptureModeSelectorStyle.symbolColor(
                isSelected: false,
                colorScheme: .dark
            ).isEqual(UIColor.white)
        )
        #expect(
            CaptureModeSelectorStyle.symbolColor(
                isSelected: false,
                colorScheme: .light
            ).isEqual(UIColor.black)
        )

        for mode in CaptureMode.allCases {
            let inactiveImage = CaptureModeSelectorStyle.symbolImage(
                for: mode,
                isSelected: false,
                colorScheme: .dark
            )
            let selectedImage = CaptureModeSelectorStyle.symbolImage(
                for: mode,
                isSelected: true,
                colorScheme: .dark
            )
            #expect(inactiveImage?.renderingMode == .alwaysOriginal)
            #expect(inactiveImage?.accessibilityLabel == mode.title)
            #expect(selectedImage?.renderingMode == .alwaysOriginal)
            #expect(selectedImage?.accessibilityLabel == mode.title)
        }
    }

    @Test("Selected thumb tint adapts to appearance and Increased Contrast")
    func selectedThumbTintIsAdaptive() {
        expectWhiteColor(
            CaptureModeSelectorStyle.selectedSegmentTintColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .dark)
            ),
            alpha: 0.82
        )
        expectWhiteColor(
            CaptureModeSelectorStyle.selectedSegmentTintColor.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            ),
            alpha: 0.96
        )
        expectWhiteColor(
            CaptureModeSelectorStyle.selectedSegmentTintColor.resolvedColor(
                with: UITraitCollection { traits in
                    traits.userInterfaceStyle = .dark
                    traits.accessibilityContrast = .high
                }
            ),
            alpha: 1
        )
    }

    @Test("Installed segment images follow the selected index contrast")
    func installedSegmentImagesFollowSelectedIndex() {
        let modes = CaptureMode.allCases
        let control = UISegmentedControl(items: modes.map(\.title))

        CaptureModeSelectorStyle.applySymbolImages(
            to: control,
            orderedModes: modes,
            selectedIndex: 1,
            colorScheme: .dark
        )

        for (index, mode) in modes.enumerated() {
            let expectedImage = CaptureModeSelectorStyle.symbolImage(
                for: mode,
                isSelected: index == 1,
                colorScheme: .dark
            )
            #expect(control.imageForSegment(at: index)?.pngData() == expectedImage?.pngData())
        }
    }

    @Test("Configured capture mode permutations retain their order")
    func configuredModeOrdersArePreserved() {
        let permutations: [[CaptureMode]] = [
            [.visual, .audio, .describe],
            [.visual, .describe, .audio],
            [.audio, .visual, .describe],
            [.audio, .describe, .visual],
            [.describe, .visual, .audio],
            [.describe, .audio, .visual]
        ]

        for permutation in permutations {
            let rawValue = permutation.map(\.rawValue).joined(separator: ",")
            #expect(CaptureMode.userOrder(from: rawValue) == permutation)
        }
    }

    @Test("Unknown or missing capture modes heal to the canonical sequence")
    func storedModeOrderHealsMissingValues() {
        #expect(CaptureMode.userOrder(from: "describe,unknown") == [
            .describe,
            .visual,
            .audio
        ])
    }

    private func expectWhiteColor(_ color: UIColor, alpha expectedAlpha: CGFloat) {
        var white: CGFloat = 0
        var alpha: CGFloat = 0

        #expect(color.getWhite(&white, alpha: &alpha))
        #expect(abs(white - 1) < 0.001)
        #expect(abs(alpha - expectedAlpha) < 0.001)
    }
}
