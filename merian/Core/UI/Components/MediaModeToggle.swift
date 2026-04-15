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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.5))
        )
        .padding(.horizontal, 48)
        .environment(\.colorScheme, .dark)
    }
}
