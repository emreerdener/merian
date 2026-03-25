import SwiftUI

/// Vertical zoom meter overlay for the camera viewfinder.
///
/// Displays a tick-mark ruler with optical stop indicators and a floating
/// horizontal line + zoom chip that tracks the current zoom factor.
/// Self-contained: reads `CameraManager` from the environment and returns
/// `EmptyView` on hardware where zoom is not supported.
/// Positioned on the right side of `MainOverlayView` via `.overlay(alignment: .trailing)`.
struct ZoomSliderView: View {
    @Environment(CameraManager.self) private var camera
    @AppStorage(UserDefaultsKeys.invertZoomDirection) private var invertZoomDirection: Bool = false

    // MARK: - Layout constants
    private let trackHeight: CGFloat = 200
    private let componentWidth: CGFloat = 80
    private let tickCount: Int = 18
    private let shortTickWidth: CGFloat = 16
    private let dotRightOffset: CGFloat = 20   // white dot distance from trailing edge
    private let chipRightOffset: CGFloat = 45  // chip trailing edge distance from component trailing

    // MARK: - Drag state
    @State private var dragStartFactor: CGFloat = 1.0
    @State private var isDragging: Bool = false
    @State private var lastHapticStop: CGFloat? = nil

    var body: some View {
        if camera.isZoomSupported {
            sliderBody
        }
    }

    // MARK: - Meter body

    private var sliderBody: some View {
        let fraction = fillFraction(for: camera.zoomFactor)
        // Default: top = max zoom, bottom = 1×. Inverted: top = 1×, bottom = max zoom.
        let indicatorY = invertZoomDirection ? fraction * trackHeight : (1.0 - fraction) * trackHeight

        return ZStack(alignment: .top) {
            rulerView
            currentZoomIndicator
                .offset(y: indicatorY)
        }
        .frame(width: componentWidth, height: trackHeight + 24)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartFactor = camera.zoomFactor
                    }
                    let dy = invertZoomDirection ? value.translation.height : -value.translation.height
                    let newFactor = min(max(dragStartFactor + deltaFactor(for: dy), 1.0), camera.maxZoomFactor)
                    camera.setZoom(factor: newFactor)
                    triggerHapticIfNeeded(factor: newFactor)
                }
                .onEnded { _ in isDragging = false }
        )
    }

    // MARK: - Ruler ticks

    private var rulerView: some View {
        let maxZoom = camera.maxZoomFactor
        let stops = camera.opticalZoomStops.filter { $0 > 1.0 }
        // Half a tick's zoom range — used to snap a tick to the nearest optical stop.
        let halfTickZoom = maxZoom > 1.0 ? (maxZoom - 1.0) / CGFloat(tickCount - 1) * 0.5 : 0
        let inverted = invertZoomDirection

        return ZStack(alignment: .top) {
            Canvas { ctx, size in
                guard maxZoom > 1.0 else { return }
                let spacing = size.height / CGFloat(tickCount - 1)

                for i in 0..<tickCount {
                    let y = CGFloat(i) * spacing
                    let t = CGFloat(i) / CGFloat(tickCount - 1)
                    // Default: top = max zoom, bottom = 1×. Inverted: top = 1×, bottom = max zoom.
                    let tickZoom = inverted
                        ? 1.0 + t * (maxZoom - 1.0)
                        : maxZoom - t * (maxZoom - 1.0)
                    let isOpticalStop = stops.contains { abs(tickZoom - $0) < halfTickZoom }

                    var line = Path()
                    let x0: CGFloat = isOpticalStop ? 0 : size.width - shortTickWidth
                    line.move(to: CGPoint(x: x0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 0.5)

                    if isOpticalStop {
                        let dotSize: CGFloat = 5
                        let dotX = size.width - dotRightOffset - dotSize / 2
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: dotX, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                            with: .color(.white)
                        )
                    }
                }
            }
            .frame(width: componentWidth, height: trackHeight)

            // Invisible tap targets centered on each optical stop tick
            ForEach(stops, id: \.self) { stop in
                let f = fillFraction(for: stop)
                let y = inverted ? f * trackHeight : (1.0 - f) * trackHeight
                Color.clear
                    .frame(width: componentWidth, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { camera.setZoom(factor: stop) }
                    .offset(y: max(0, y - 11))
            }
        }
    }

    // MARK: - Current zoom indicator

    private var currentZoomIndicator: some View {
        ZStack(alignment: .trailing) {
            // Full-width horizontal rule
            Color.white.opacity(0.9)
                .frame(maxWidth: .infinity, maxHeight: 0.5)

            // Yellow zoom chip, trailing-offset by chipRightOffset
            Text(zoomLabel(for: camera.zoomFactor))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(red: 1.0, green: 204.0 / 255.0, blue: 0.0, opacity: 0.8)))
                .fixedSize()
                .alignmentGuide(.trailing) { d in d.width + chipRightOffset }
        }
        .frame(width: componentWidth, height: 22)
    }

    // MARK: - Math

    private func fillFraction(for factor: CGFloat) -> CGFloat {
        guard camera.maxZoomFactor > 1.0 else { return 0 }
        return min(max((factor - 1.0) / (camera.maxZoomFactor - 1.0), 0), 1)
    }

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
        let stops = camera.opticalZoomStops
        for stop in stops {
            if abs(factor - stop) < 0.05 && lastHapticStop != stop {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                lastHapticStop = stop
                return
            }
        }
        if lastHapticStop != nil && stops.allSatisfy({ abs(factor - $0) >= 0.07 }) {
            lastHapticStop = nil
        }
    }
}
