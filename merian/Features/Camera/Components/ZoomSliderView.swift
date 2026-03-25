import SwiftUI

/// Vertical zoom meter overlay for the camera viewfinder.
///
/// Displays a tick-mark ruler with optical stop indicators and a floating
/// zoom chip that tracks the current zoom factor. Zoom is controlled via
/// dragging the slider, or pinch/swipe gestures on the full viewfinder.
/// Self-contained: reads `CameraManager` from the environment and returns
/// `EmptyView` on hardware where zoom is not supported.
struct ZoomSliderView: View {
    @Environment(CameraManager.self) private var camera
    @AppStorage(UserDefaultsKeys.invertZoomDirection) private var invertZoomDirection: Bool = false
    @AppStorage(UserDefaultsKeys.zoomSideLeft) private var zoomSideLeft: Bool = false

    // MARK: - Layout constants
    private let trackHeight: CGFloat = 220
    private let componentWidth: CGFloat = 52
    private let tickCount: Int = 32
    private let shortTickWidth: CGFloat = 18
    private let dotRightOffset: CGFloat = 18   // white dot distance from trailing edge
    private let opticalTickInset: CGFloat = 4  // extra gap between dot and its tick
    // Aligns indicator center with tick positions: rulerView padding(11) + canvas y-start(4) − half indicator height(10) = 5
    private let indicatorTickOffset: CGFloat = 5
    private let zoomYellow = Color(red: 1.0, green: 204.0 / 255.0, blue: 0.0)

    // MARK: - State
    @State private var isActivelyZooming: Bool = false
    @State private var zoomIdleTask: Task<Void, Never>? = nil
    @State private var lastHapticTick: Int? = nil
    @State private var dragStartFactor: CGFloat = 1.0
    @State private var isDragging: Bool = false

    var body: some View {
        Group {
            if camera.isZoomSupported {
                sliderBody
                    .scaleEffect(x: zoomSideLeft ? -1 : 1, y: 1)
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.5), value: camera.isZoomSupported)
        .onChange(of: camera.zoomFactor) { _, newValue in
            isActivelyZooming = true
            triggerHapticIfNeeded(factor: newValue)
            zoomIdleTask?.cancel()
            zoomIdleTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                await MainActor.run { isActivelyZooming = false }
            }
        }
    }

    // MARK: - Meter body

    private var sliderBody: some View {
        let fraction = fillFraction(for: camera.zoomFactor)
        // Default: top = max zoom, bottom = 1×. Inverted: top = 1×, bottom = max zoom.
        let indicatorY = indicatorTickOffset + (invertZoomDirection ? fraction * trackHeight : (1.0 - fraction) * trackHeight)

        return ZStack(alignment: .top) {
            rulerView
                .padding(.top, 11)
            currentZoomIndicator
                .offset(y: indicatorY)
                .animation(isDragging ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: indicatorY)
        }
        .frame(width: componentWidth, height: trackHeight + 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartFactor = camera.zoomFactor
                    }
                    // Log-space delta gives 1:1 visual tracking on the logarithmic ruler.
                    // newFactor = startFactor * exp(sign * (dy / trackHeight) * log(maxZoom))
                    let dy = invertZoomDirection ? value.translation.height : -value.translation.height
                    let logMax = log(camera.maxZoomFactor)
                    let newFactor = min(max(dragStartFactor * exp((dy / trackHeight) * logMax), 1.0), camera.maxZoomFactor)
                    camera.setZoom(factor: newFactor)
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

        return Canvas { ctx, size in
            guard maxZoom > 1.0 else { return }
            let spacing = trackHeight / CGFloat(tickCount - 1)

            for i in 0..<tickCount {
                let y = 4.0 + CGFloat(i) * spacing
                let t = CGFloat(i) / CGFloat(tickCount - 1)
                // Default: top = max zoom, bottom = 1×. Inverted: top = 1×, bottom = max zoom.
                let tickZoom = inverted
                    ? 1.0 + t * (maxZoom - 1.0)
                    : maxZoom - t * (maxZoom - 1.0)
                let isOpticalStop = stops.contains { abs(tickZoom - $0) < halfTickZoom }
                // Max zoom tick: i=0 in default (top), i=tickCount-1 in inverted (bottom)
                let isMaxZoom = inverted ? i == tickCount - 1 : i == 0

                var line = Path()
                let tickLength: CGFloat
                let x0: CGFloat
                if isMaxZoom {
                    tickLength = shortTickWidth
                    x0 = size.width - tickLength + opticalTickInset
                } else {
                    tickLength = isOpticalStop ? shortTickWidth : shortTickWidth * 0.6
                    x0 = size.width - tickLength + (isOpticalStop ? opticalTickInset : 0)
                }
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))

                let tickColor: Color = isOpticalStop || isMaxZoom ? .white.opacity(0.8) : .white.opacity(0.45)
                ctx.stroke(line, with: .color(tickColor), lineWidth: 0.5)

                if isMaxZoom {
                    let dotSize: CGFloat = 4
                    let dotX = size.width - dotRightOffset - dotSize / 2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                        with: .color(.white.opacity(0.9))
                    )
                } else if isOpticalStop {
                    let dotSize: CGFloat = 4
                    let dotX = size.width - dotRightOffset - dotSize / 2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                        with: .color(.white.opacity(0.9))
                    )
                }
            }
        }
        .frame(width: componentWidth, height: trackHeight + 8)
    }

    // MARK: - Current zoom indicator

    private var currentZoomIndicator: some View {
        let showText = isActivelyZooming || abs(camera.zoomFactor - 1.0) < 0.01

        return HStack(spacing: 0) {
            Spacer(minLength: 0)

            if showText {
                Text(zoomLabel(for: camera.zoomFactor))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .contentTransition(.numericText())
                    .scaleEffect(x: zoomSideLeft ? -1 : 1, y: 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(zoomYellow))
                    .fixedSize()
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else {
                Circle()
                    .fill(zoomYellow)
                    .frame(width: 5, height: 5)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            // Hair-line connector to the ruler ticks — subtler when showing the dot
            Color.white
                .frame(width: shortTickWidth, height: showText ? 1.5 : 0.5)
                .opacity(showText ? 0.7 : 0.15)
        }
        .frame(width: componentWidth, height: 20)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showText)
    }

    // MARK: - Math

    private func fillFraction(for factor: CGFloat) -> CGFloat {
        let maxZoom = camera.maxZoomFactor
        guard maxZoom > 1.0 else { return 0 }
        let logMax = log(maxZoom)
        guard logMax > 0 else { return 0 }
        return min(max(log(max(factor, 1.0)) / logMax, 0), 1)
    }

    // MARK: - Haptics

    /// Fires on every tick crossing. Maps both the current factor and optical stops into
    /// tick-index space so optical stop detection is accurate on the logarithmic scale.
    private func triggerHapticIfNeeded(factor: CGFloat) {
        guard camera.maxZoomFactor > 1.0 else { return }

        let fraction = fillFraction(for: factor)
        let currentTick = Int((fraction * CGFloat(tickCount - 1)).rounded())
        guard currentTick != lastHapticTick else { return }
        lastHapticTick = currentTick

        // Map optical stops to their nearest tick indices in log space.
        let logMax = log(camera.maxZoomFactor)
        let opticalStopTicks = Set(camera.opticalZoomStops.map { stop -> Int in
            let f = log(max(stop, 1.0)) / logMax
            return Int((f * CGFloat(tickCount - 1)).rounded())
        })

        if opticalStopTicks.contains(currentTick) {
            HapticManager.shared.triggerHeavyImpact(intensity: 1.0)
        } else {
            HapticManager.shared.triggerLightImpact(intensity: 0.4)
        }
    }

    // MARK: - Formatting

    private func zoomLabel(for factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))×"
        }
        return String(format: "%.1f×", rounded)
    }
}
