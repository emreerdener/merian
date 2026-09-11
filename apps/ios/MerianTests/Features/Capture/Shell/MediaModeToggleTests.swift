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
            CaptureModeSelectorStyle.controlWidth
                / CGFloat(CaptureMode.allCases.count) >= 44
        )
        let horizontalSymbolPadding = (
            CaptureModeSelectorStyle.controlWidth
                / CGFloat(CaptureMode.allCases.count)
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
            #expect(
                control.imageForSegment(at: index)?.pngData()
                    == expectedImage?.pngData()
            )
        }
    }

    @Test("Native value changes update the SwiftUI selection binding")
    func nativeValueChangeUpdatesBinding() throws {
        try expectNativeSelectionUpdate(for: [.valueChanged])
    }

    @Test("Native primary actions update the SwiftUI selection binding")
    func nativePrimaryActionUpdatesBinding() throws {
        try expectNativeSelectionUpdate(for: [.primaryActionTriggered])
    }

    @Test("Duplicate native selector events notify once")
    func duplicateNativeEventsNotifyOnce() throws {
        try expectNativeSelectionUpdate(for: [
            .valueChanged,
            .primaryActionTriggered
        ])
    }

    private func expectNativeSelectionUpdate(
        for events: [UIControl.Event]
    ) throws {
        let selection = CaptureModeSelectionBox(mode: .visual)
        var modeChangeCount = 0
        let (window, control) = try hostedSelector(
            selection: selection,
            onModeChange: { modeChangeCount += 1 }
        )
        defer { window.isHidden = true }

        let controlCenter = control.convert(
            CGPoint(x: control.bounds.midX, y: control.bounds.midY),
            to: window
        )
        let hitView = window.hitTest(controlCenter, with: nil)
        #expect(
            hitView === control
                || hitView?.isDescendant(of: control) == true
        )

        control.selectedSegmentIndex = 1
        for event in events {
            control.sendActions(for: event)
        }

        #expect(selection.mode == .audio)
        #expect(modeChangeCount == 1)
    }

    private func hostedSelector(
        selection: CaptureModeSelectionBox,
        onModeChange: @escaping () -> Void
    ) throws -> (UIWindow, UISegmentedControl) {
        let subject = MediaModeToggle(
            activeMode: Binding(
                get: { selection.mode },
                set: { selection.mode = $0 }
            ),
            isDragging: .constant(false),
            orderedModes: CaptureMode.allCases,
            onModeChange: onModeChange
        )
        let host = UIHostingController(rootView: subject)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()

        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let control = try #require(
            firstSegmentedControl(in: host.view)
        )
        return (window, control)
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

    private func expectWhiteColor(
        _ color: UIColor,
        alpha expectedAlpha: CGFloat
    ) {
        var white: CGFloat = 0
        var alpha: CGFloat = 0

        #expect(color.getWhite(&white, alpha: &alpha))
        #expect(abs(white - 1) < 0.001)
        #expect(abs(alpha - expectedAlpha) < 0.001)
    }

    private func firstSegmentedControl(
        in view: UIView
    ) -> UISegmentedControl? {
        if let control = view as? UISegmentedControl {
            return control
        }

        for subview in view.subviews {
            if let control = firstSegmentedControl(in: subview) {
                return control
            }
        }
        return nil
    }
}

@MainActor
private final class CaptureModeSelectionBox {
    var mode: CaptureMode

    init(mode: CaptureMode) {
        self.mode = mode
    }
}
