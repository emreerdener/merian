import SwiftUI

/// Vertical zoom slider overlay for the camera viewfinder.
///
/// Self-contained: reads `CameraManager` from the environment and returns `EmptyView`
/// on hardware where `maxAvailableVideoZoomFactor < 2.0` (single-lens devices).
/// Positioned on the right side of `MainOverlayView` via `.overlay(alignment: .trailing)`.
struct ZoomSliderView: View {
    @Environment(CameraManager.self) private var camera

    // MARK: - Layout constants
    private let trackHeight: CGFloat = 200
    private let trackWidth:  CGFloat = 6
    private let thumbSize:   CGFloat = 22
    private let hapticStops: [CGFloat] = [1.0, 2.0, 3.0]

    // MARK: - Drag state
    @State private var dragStartFactor: CGFloat = 1.0
    @State private var isDragging: Bool = false
    @State private var lastHapticStop: CGFloat? = nil

    var body: some View {
        if camera.isZoomSupported {
            sliderBody
        }
    }

    // MARK: - Slider

    private var sliderBody: some View {
        let fraction = fillFraction(for: camera.zoomFactor)
        let thumbY   = fraction * trackHeight

        return ZStack(alignment: .bottom) {
            // Track background
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .frame(width: trackWidth, height: trackHeight)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )

            // Thermometer fill
            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: trackWidth, height: max(trackWidth, trackHeight * fraction))

            // Thumb + label
            VStack(spacing: 4) {
                Text(zoomLabel(for: camera.zoomFactor))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .fixedSize()

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            }
            .offset(y: -thumbY)
        }
        .frame(width: thumbSize * 2, height: trackHeight + thumbSize + 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartFactor = camera.zoomFactor
                    }
                    let delta = deltaFactor(for: -value.translation.height)
                    let proposed = dragStartFactor + delta
                    let newFactor = min(max(proposed, 1.0), camera.maxZoomFactor)
                    camera.setZoom(factor: newFactor)
                    triggerHapticIfNeeded(factor: newFactor)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }

    // MARK: - Math

    /// Normalizes a zoom factor to [0, 1] across the full track height.
    private func fillFraction(for factor: CGFloat) -> CGFloat {
        guard camera.maxZoomFactor > 1.0 else { return 0 }
        return min(max((factor - 1.0) / (camera.maxZoomFactor - 1.0), 0), 1)
    }

    /// Maps a drag delta in points to a zoom factor delta.
    /// The full 200pt track corresponds to the entire zoom range.
    private func deltaFactor(for deltaPoints: CGFloat) -> CGFloat {
        (deltaPoints / trackHeight) * (camera.maxZoomFactor - 1.0)
    }

    // MARK: - Formatting

    private func zoomLabel(for factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%.1f×", rounded)
    }

    // MARK: - Haptics

    private func triggerHapticIfNeeded(factor: CGFloat) {
        for stop in hapticStops where stop <= camera.maxZoomFactor {
            if abs(factor - stop) < 0.05 && lastHapticStop != stop {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                lastHapticStop = stop
                return
            }
        }
        // Reset hysteresis so the haptic can fire again on re-crossing.
        if lastHapticStop != nil && hapticStops.allSatisfy({ abs(factor - $0) >= 0.07 }) {
            lastHapticStop = nil
        }
    }
}
