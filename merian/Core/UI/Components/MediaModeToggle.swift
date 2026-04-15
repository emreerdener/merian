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
}

/// A standard iOS native segmented picker controlling the active capture mode.
/// This replaces the custom drag-tracking glassmorphic toggle to ensure 
/// bulletproof layout stability alongside complete iOS UIKit accessibility support.
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    @Binding var isDragging: Bool // Maintained for signature compatibility; unused internally
    let onModeChange: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(activeMode: Binding<CaptureMode>, isDragging: Binding<Bool>, onModeChange: @escaping () -> Void) {
        self._activeMode = activeMode
        self._isDragging = isDragging
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
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 1)
        .padding(.bottom, 3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
                )
        )
        .clipShape(Capsule())
        .scaleEffect(1.1)
        .padding(.horizontal, 48)
        .environment(\.colorScheme, activeMode == .visual ? .dark : colorScheme)
    }
}
