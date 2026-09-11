import SwiftUI
import UIKit

/// A native icon-only segmented control for the active capture mode.
/// UIKit owns the selection thumb, Liquid Glass interaction, and accessibility
/// semantics while SwiftUI continues to own the capture-mode binding and layout.
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    // Maintained for initializer compatibility; UIKit owns drag interaction.
    @Binding var isDragging: Bool
    let orderedModes: [CaptureMode]
    let onModeChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        activeMode: Binding<CaptureMode>,
        isDragging: Binding<Bool>,
        orderedModes: [CaptureMode],
        onModeChange: @escaping () -> Void
    ) {
        self._activeMode = activeMode
        self._isDragging = isDragging
        self.orderedModes = orderedModes
        self.onModeChange = onModeChange
    }

    var body: some View {
        NativeCaptureModeSegmentedControl(
            activeMode: $activeMode,
            orderedModes: orderedModes,
            onModeChange: onModeChange
        )
        .frame(
            width: CaptureModeSelectorStyle.controlWidth,
            height: CaptureModeSelectorStyle.controlHeight
        )
        .modifier(CaptureModeSelectorGlassModifier())
        .environment(\.colorScheme, activeMode == .visual ? .dark : colorScheme)
    }
}

private struct CaptureModeSelectorGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .clipShape(Capsule())
        }
    }
}

@MainActor
private final class CaptureModeSegmentedControl: UISegmentedControl {
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height = CaptureModeSelectorStyle.controlHeight
        return size
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var fittedSize = super.sizeThatFits(size)
        fittedSize.height = CaptureModeSelectorStyle.controlHeight
        return fittedSize
    }
}

private struct CaptureModeInstalledImageState: Equatable {
    let modeIdentifiers: [String]
    let selectedIndex: Int
    let colorScheme: ColorScheme
}

@MainActor
private struct NativeCaptureModeSegmentedControl: UIViewRepresentable {
    @Binding var activeMode: CaptureMode
    let orderedModes: [CaptureMode]
    let onModeChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = CaptureModeSegmentedControl(
            frame: .zero,
            actions: makeActions(coordinator: context.coordinator)
        )
        // Action-backed segments report both documented selection events.
        // Route either signal through the same guarded coordinator so native,
        // assistive, and automated activation share one binding path.
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: [.valueChanged, .primaryActionTriggered]
        )
        configure(control)
        control.selectedSegmentIndex = selectedSegmentIndex
        context.coordinator.refreshInstalledImages(
            in: control,
            force: true
        )
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self

        let modeIdentifiers = orderedModes.map(\.rawValue)
        let rebuiltSegments: Bool
        if context.coordinator.modeIdentifiers != modeIdentifiers
            || control.numberOfSegments != orderedModes.count {
            control.removeAllSegments()
            for (index, action) in makeActions(
                coordinator: context.coordinator
            ).enumerated() {
                control.insertSegment(action: action, at: index, animated: false)
            }
            context.coordinator.modeIdentifiers = modeIdentifiers
            rebuiltSegments = true
        } else {
            rebuiltSegments = false
        }

        configure(control)

        // Keep the SwiftUI-owned selection authoritative when the pager changes.
        if control.selectedSegmentIndex != selectedSegmentIndex {
            control.selectedSegmentIndex = selectedSegmentIndex
        }
        context.coordinator.refreshInstalledImages(
            in: control,
            force: rebuiltSegments
        )
    }

    private var selectedSegmentIndex: Int {
        orderedModes.firstIndex(of: activeMode)
            ?? UISegmentedControl.noSegment
    }

    private func makeActions(coordinator: Coordinator) -> [UIAction] {
        orderedModes.map { makeAction(for: $0, coordinator: coordinator) }
    }

    private func makeAction(
        for mode: CaptureMode,
        coordinator: Coordinator
    ) -> UIAction {
        let action = UIAction(
            title: mode.title,
            image: CaptureModeSelectorStyle.symbolImage(
                for: mode,
                isSelected: mode == activeMode,
                colorScheme: colorScheme
            ),
            identifier: UIAction.Identifier(mode.rawValue),
            state: mode == activeMode ? .on : .off
        ) { [weak coordinator] _ in
            coordinator?.select(mode)
        }
        action.selectedImage = CaptureModeSelectorStyle.symbolImage(
            for: mode,
            isSelected: true,
            colorScheme: colorScheme
        )
        action.accessibilityLabel = mode.title
        return action
    }

    private func configure(_ control: UISegmentedControl) {
        control.apportionsSegmentWidthsByContent = false
        control.selectedSegmentTintColor =
            CaptureModeSelectorStyle.selectedSegmentTintColor
        control.accessibilityIdentifier = "CaptureModeToggle"
        control.accessibilityLabel = "Capture mode"
        control.accessibilityValue = activeMode.title
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeCaptureModeSegmentedControl
        var modeIdentifiers: [String]
        private var installedImageState: CaptureModeInstalledImageState?

        init(parent: NativeCaptureModeSegmentedControl) {
            self.parent = parent
            self.modeIdentifiers = parent.orderedModes.map(\.rawValue)
        }

        @objc
        func selectionChanged(_ control: UISegmentedControl) {
            guard parent.orderedModes.indices.contains(
                control.selectedSegmentIndex
            ) else {
                return
            }
            refreshInstalledImages(in: control)
            select(parent.orderedModes[control.selectedSegmentIndex])
        }

        func refreshInstalledImages(
            in control: UISegmentedControl,
            force: Bool = false
        ) {
            let state = CaptureModeInstalledImageState(
                modeIdentifiers: parent.orderedModes.map(\.rawValue),
                selectedIndex: control.selectedSegmentIndex,
                colorScheme: parent.colorScheme
            )
            guard force || state != installedImageState else { return }

            CaptureModeSelectorStyle.applySymbolImages(
                to: control,
                orderedModes: parent.orderedModes,
                selectedIndex: state.selectedIndex,
                colorScheme: state.colorScheme
            )
            installedImageState = state
        }

        func select(_ mode: CaptureMode) {
            guard mode != parent.activeMode else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                parent.activeMode = mode
            }
            parent.onModeChange()
        }
    }
}
