import SwiftUI

/// All capture modes available from the camera root view.
/// Adding a new case automatically adds a segment to `MediaModeToggle`
/// and a page to the `CameraRootView` pager — no other changes needed.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
    case sighting
}

/// A glassmorphic capsule toggle controlling the active capture mode.
///
/// Pill math is index-driven so adding new `CaptureMode` cases requires no
/// changes here — `segmentWidth` divides the total width by `allCases.count`
/// and the drag gesture navigates by index ± 1.
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    let onModeChange: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var toggleSize: CGSize = .zero

    // MARK: - Layout Math

    private var segmentCount: CGFloat { CGFloat(CaptureMode.allCases.count) }
    private var segmentWidth: CGFloat { toggleSize.width / segmentCount }

    private var activeIndex: Int {
        CaptureMode.allCases.firstIndex(of: activeMode) ?? 0
    }

    /// Pill x-position: index-based base + clamped drag offset, bounded to valid segment range.
    private var pillX: CGFloat {
        let base = CGFloat(activeIndex) * segmentWidth
        let clamped = max(-segmentWidth, min(dragOffset, segmentWidth))
        return max(0, min(base + clamped, toggleSize.width - segmentWidth))
    }

    /// Interpolates label color from pill position so it transitions smoothly during drag.
    private func labelColor(for mode: CaptureMode) -> Color {
        guard segmentWidth > 0 else {
            return activeMode == mode ? .black : .white.opacity(0.85)
        }
        let modeIndex = CGFloat(CaptureMode.allCases.firstIndex(of: mode) ?? 0)
        let pilledIndex = pillX / segmentWidth
        let isActive = abs(modeIndex - pilledIndex) < 0.5
        return isActive ? .black : .white.opacity(0.85)
    }

    // MARK: - Mode Metadata

    private func icon(for mode: CaptureMode) -> String {
        switch mode {
        case .visual:   return "viewfinder"
        case .audio:    return "waveform"
        case .sighting: return "eye"
        }
    }

    private func label(for mode: CaptureMode) -> String {
        switch mode {
        case .visual:   return "Scan"
        case .audio:    return "Record"
        case .sighting: return "Sighting"
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        activeMode = mode
                    }
                    onModeChange()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: icon(for: mode))
                        Text(label(for: mode))
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(labelColor(for: mode))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        // Size probe
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { toggleSize = geo.size }
                    .onChange(of: geo.size) { _, size in toggleSize = size }
            }
        }
        // White pill lives BEHIND the buttons so text renders on top and stays readable.
        .background(alignment: .leading) {
            if toggleSize != .zero {
                Capsule()
                    .fill(Color.white)
                    .frame(width: segmentWidth, height: toggleSize.height)
                    .offset(x: pillX)
            }
        }
        // Drag gesture: only activates when starting on the active segment,
        // then commits to adjacent mode on threshold cross.
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { value in
                    guard segmentWidth > 0 else { return }
                    let startSegment = Int(value.startLocation.x / segmentWidth)
                    guard startSegment == activeIndex else { return }
                    dragOffset = max(-segmentWidth, min(value.translation.width, segmentWidth))
                }
                .onEnded { value in
                    defer {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                    }
                    guard segmentWidth > 0 else { return }
                    let startSegment = Int(value.startLocation.x / segmentWidth)
                    guard startSegment == activeIndex else { return }

                    let threshold = segmentWidth / 2
                    let cases = CaptureMode.allCases
                    if dragOffset > threshold && activeIndex < cases.count - 1 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeMode = cases[activeIndex + 1]
                        }
                        onModeChange()
                    } else if dragOffset < -threshold && activeIndex > 0 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeMode = cases[activeIndex - 1]
                        }
                        onModeChange()
                    }
                }
        )
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}
