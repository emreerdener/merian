import SwiftUI

/// All capture modes available from the camera root view.
/// Adding a new case automatically adds a segment to `MediaModeToggle`
/// and a page to the `CameraRootView` pager — no other changes needed.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
    case describe
}

/// A glassmorphic capsule toggle controlling the active capture mode.
///
/// Each segment sizes to its natural content width. Visual drag state is tracked
/// separately from the committed `activeMode` binding so the pager's snap physics
/// (driven by the same `captureMode` state) do not interfere while the drag is live.
/// `activeMode` is only written in `onEnded`, after the gesture is complete.
struct MediaModeToggle: View {
    @Binding var activeMode: CaptureMode
    @Binding var isDragging: Bool
    let onModeChange: () -> Void

    /// Visual-only mode while a drag is in flight. `nil` at rest.
    /// Decoupled from `activeMode` so writing the binding (which drives the pager)
    /// only happens once, in `onEnded`, not on every `onChanged` event.
    @State private var dragMode: CaptureMode?
    @State private var dragOffset: CGFloat = 0
    @State private var segmentWidths: [Int: CGFloat] = [:]

    // MARK: - Layout Math

    private var cases: [CaptureMode] { CaptureMode.allCases }

    /// The mode used for all visual calculations (pill position, label colours).
    /// Tracks `dragMode` while dragging; falls back to committed `activeMode` at rest.
    private var displayMode: CaptureMode { dragMode ?? activeMode }

    private var displayIndex: Int { cases.firstIndex(of: displayMode) ?? 0 }

    private var totalWidth: CGFloat {
        cases.indices.reduce(0) { $0 + (segmentWidths[$1] ?? 0) }
    }

    private var displayPillWidth: CGFloat { segmentWidths[displayIndex] ?? 0 }

    private func xOffset(for index: Int) -> CGFloat {
        (0..<index).reduce(0) { $0 + (segmentWidths[$1] ?? 0) }
    }

    private func indexForX(_ x: CGFloat) -> Int {
        var cumulative: CGFloat = 0
        for i in cases.indices {
            cumulative += segmentWidths[i] ?? 0
            if x < cumulative { return i }
        }
        return cases.count - 1
    }

    private var pillX: CGFloat {
        let base = xOffset(for: displayIndex)
        return max(0, min(base + dragOffset, totalWidth - displayPillWidth))
    }

    private func labelColor(for mode: CaptureMode) -> Color {
        guard let idx = cases.firstIndex(of: mode),
              let w = segmentWidths[idx], w > 0 else {
            return displayMode == mode ? .black : .white.opacity(0.85)
        }
        let segMid = xOffset(for: idx) + w / 2
        let pillMid = pillX + displayPillWidth / 2
        return abs(pillMid - segMid) < w / 2 ? .black : .white.opacity(0.85)
    }

    // MARK: - Mode Metadata

    private func icon(for mode: CaptureMode) -> String {
        switch mode {
        case .visual:   return "viewfinder"
        case .audio:    return "waveform"
        case .describe: return "text.alignleft"
        }
    }

    private func label(for mode: CaptureMode) -> String {
        switch mode {
        case .visual:   return "Scan"
        case .audio:    return "Record"
        case .describe: return "Describe"
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cases.enumerated()), id: \.element) { index, mode in
                Button(action: {
                    // Suppress tap actions while a drag is in progress.
                    guard dragMode == nil else { return }
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
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { segmentWidths[index] = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in segmentWidths[index] = w }
                    }
                }
            }
        }
        // White pill lives BEHIND the buttons; width and position match displayMode.
        .background(alignment: .leading) {
            if displayPillWidth > 0 {
                Capsule()
                    .fill(Color.white)
                    .frame(width: displayPillWidth)
                    .frame(maxHeight: .infinity)
                    .offset(x: pillX)
            }
        }
        // simultaneousGesture lets drag fire even when the finger starts over a Button child.
        // The ScrollView's pan also fires simultaneously, but captureModeScrollBinding guards
        // against writing an unchanged value, so no spurious captureMode updates occur.
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { value in
                    guard !segmentWidths.isEmpty, totalWidth > 0 else { return }

                    // Mode selection uses the actual finger position so the threshold is
                    // exactly the visual segment boundary — no offset math, no hysteresis.
                    let fingerX = max(0, min(value.location.x, totalWidth - 1))
                    let proposedIndex = indexForX(fingerX)
                    let proposedMode = cases[proposedIndex]

                    // Seed dragMode from the committed mode on the first event.
                    let prevMode = dragMode ?? activeMode
                    if dragMode == nil {
                        dragMode = activeMode
                        isDragging = true  // disable the pager scroll for the drag's lifetime
                    }

                    // Haptic feedback when the visual mode crosses a segment boundary.
                    if proposedMode != prevMode { onModeChange() }
                    dragMode = proposedMode

                    // Pill tracks the finger translation for a physical drag feel.
                    let gestureStartIndex = indexForX(max(0, value.startLocation.x))
                    let rawPillX = max(0, min(
                        xOffset(for: gestureStartIndex) + value.translation.width, totalWidth
                    ))
                    // dragOffset is relative to proposedIndex's base so pillX == rawPillX.
                    dragOffset = rawPillX - xOffset(for: proposedIndex)
                }
                .onEnded { value in
                    guard !segmentWidths.isEmpty, totalWidth > 0 else {
                        isDragging = false
                        dragMode = nil
                        dragOffset = 0
                        return
                    }
                    let fingerX = max(0, min(value.location.x, totalWidth - 1))
                    let finalMode = cases[indexForX(fingerX)]

                    // Re-enable the pager before committing the mode so scrollPosition(id:)
                    // can animate the page snap to the final position.
                    isDragging = false

                    // Commit: write the binding exactly once, after the gesture is complete.
                    if finalMode != activeMode {
                        activeMode = finalMode
                        onModeChange()
                    }

                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        dragOffset = 0
                        dragMode = nil
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
