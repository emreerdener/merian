import SwiftUI

/// All capture modes available from the camera root view.
/// Adding a new case automatically adds a segment to `MediaModeToggle`
/// and a page to the `CameraRootView` pager — no other changes needed.
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

/// A standard iOS native segmented picker controlling the active capture mode.
/// This replaces the custom drag-tracking glassmorphic toggle to ensure 
/// bulletproof layout stability alongside complete iOS UIKit accessibility support.
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    @Binding var isDragging: Bool // Maintained for signature compatibility; unused internally
    let orderedModes: [CaptureMode]
    let onModeChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(activeMode: Binding<CaptureMode>, isDragging: Binding<Bool>, orderedModes: [CaptureMode], onModeChange: @escaping () -> Void) {
        self._activeMode = activeMode
        self._isDragging = isDragging
        self.orderedModes = orderedModes
        self.onModeChange = onModeChange
        
        // Explicitly flush the empty proxy from the global app memory to restore Apple's native sliding thumb!
        UISegmentedControl.appearance().setBackgroundImage(nil, for: .normal, barMetrics: .default)
        UISegmentedControl.appearance().setDividerImage(nil, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
    }

    var body: some View {
        Picker("Capture Mode", selection: Binding(
            get: { activeMode },
            set: { newMode in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    activeMode = newMode
                }
                onModeChange()
            }
        )) {
            ForEach(orderedModes, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 1)
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.8))
        .clipShape(Capsule())
        .scaleEffect(1.1)
        .padding(.horizontal, 48)
        .environment(\.colorScheme, activeMode == .visual ? .dark : colorScheme)
    }
}
