import SwiftUI
import UIKit

/// All capture modes available from the camera root view.
/// Adding a case requires matching pager content, settings copy, persistence
/// migration behavior, and startup-mode coverage.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
    case describe
    
    var title: String {
        switch self {
        case .visual:   return "Scan"
        case .audio:    return "Record"
        case .describe: return "Describe"
        }
    }

    var symbolName: String {
        switch self {
        case .visual:   return "viewfinder"
        case .audio:    return "waveform"
        case .describe: return "text.bubble"
        }
    }
    
    /// Parses a comma-separated string into a safe array of CaptureModes.
    /// Automatically detects missing enums across updates or migrations and 
    /// appends them to heal the backing store.
    static func userOrder(from raw: String) -> [CaptureMode] {
        var decoded = raw
            .split(separator: ",")
            .compactMap { CaptureMode(rawValue: String($0)) }
        let missing = CaptureMode.allCases.filter { !decoded.contains($0) }
        if !missing.isEmpty {
            decoded.append(contentsOf: missing)
        }
        return decoded
    }
}

enum CaptureModeSelectorStyle {
    static let controlWidth: CGFloat = 200
    static let controlHeight: CGFloat = 56
    static let symbolPointSize: CGFloat = 24
    static let describeContentClearance: CGFloat = 82

    static let selectedSegmentTintColor = UIColor { traits in
        if traits.accessibilityContrast == .high {
            return .white
        }

        return traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.82)
            : UIColor.white.withAlphaComponent(0.96)
    }

    static func symbolColor(isSelected: Bool, colorScheme: ColorScheme) -> UIColor {
        if isSelected || colorScheme == .light {
            return .black
        }

        return .white
    }

    static func symbolImage(
        for mode: CaptureMode,
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: symbolPointSize,
            weight: .semibold
        )
        guard let symbol = UIImage(
            systemName: mode.symbolName,
            withConfiguration: configuration
        ) else {
            return nil
        }

        let image = symbol.withTintColor(
            symbolColor(isSelected: isSelected, colorScheme: colorScheme),
            renderingMode: .alwaysOriginal
        )
        image.accessibilityLabel = mode.title
        return image
    }

    static func applySymbolImages(
        to control: UISegmentedControl,
        orderedModes: [CaptureMode],
        selectedIndex: Int,
        colorScheme: ColorScheme
    ) {
        for (index, mode) in orderedModes.enumerated() {
            guard index < control.numberOfSegments else { continue }
            control.setImage(
                symbolImage(
                    for: mode,
                    isSelected: index == selectedIndex,
                    colorScheme: colorScheme
                ),
                forSegmentAt: index
            )
        }
    }
}

/// A native icon-only segmented control for the active capture mode.
/// UIKit owns the selection thumb, Liquid Glass interaction, and accessibility
/// semantics while SwiftUI continues to own the capture-mode binding and layout.
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    @Binding var isDragging: Bool // Maintained for signature compatibility; unused internally
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
        control.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: .valueChanged
        )
        configure(control)
        control.selectedSegmentIndex = selectedSegmentIndex
        CaptureModeSelectorStyle.applySymbolImages(
            to: control,
            orderedModes: orderedModes,
            selectedIndex: selectedSegmentIndex,
            colorScheme: colorScheme
        )
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self

        let modeIdentifiers = orderedModes.map(\.rawValue)
        if context.coordinator.modeIdentifiers != modeIdentifiers
            || control.numberOfSegments != orderedModes.count {
            control.removeAllSegments()
            for (index, action) in makeActions(coordinator: context.coordinator).enumerated() {
                control.insertSegment(action: action, at: index, animated: false)
            }
            context.coordinator.modeIdentifiers = modeIdentifiers
        }

        configure(control)

        // Keep the SwiftUI-owned selection authoritative when the pager changes.
        if control.selectedSegmentIndex != selectedSegmentIndex {
            control.selectedSegmentIndex = selectedSegmentIndex
        }
        CaptureModeSelectorStyle.applySymbolImages(
            to: control,
            orderedModes: orderedModes,
            selectedIndex: selectedSegmentIndex,
            colorScheme: colorScheme
        )
    }

    private var selectedSegmentIndex: Int {
        orderedModes.firstIndex(of: activeMode) ?? UISegmentedControl.noSegment
    }

    private func makeActions(coordinator: Coordinator) -> [UIAction] {
        orderedModes.map { makeAction(for: $0, coordinator: coordinator) }
    }

    private func makeAction(for mode: CaptureMode, coordinator: Coordinator) -> UIAction {
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
        control.selectedSegmentTintColor = CaptureModeSelectorStyle.selectedSegmentTintColor
        control.accessibilityIdentifier = "CaptureModeToggle"
        control.accessibilityLabel = "Capture mode"
        control.accessibilityValue = activeMode.title
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeCaptureModeSegmentedControl
        var modeIdentifiers: [String]

        init(parent: NativeCaptureModeSegmentedControl) {
            self.parent = parent
            self.modeIdentifiers = parent.orderedModes.map(\.rawValue)
        }

        @objc
        func selectionChanged(_ control: UISegmentedControl) {
            guard parent.orderedModes.indices.contains(control.selectedSegmentIndex) else {
                return
            }
            CaptureModeSelectorStyle.applySymbolImages(
                to: control,
                orderedModes: parent.orderedModes,
                selectedIndex: control.selectedSegmentIndex,
                colorScheme: parent.colorScheme
            )
            select(parent.orderedModes[control.selectedSegmentIndex])
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
