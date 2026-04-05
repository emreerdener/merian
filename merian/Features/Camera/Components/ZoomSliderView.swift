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
    @AppStorage(UserDefaultsKeys.zoomSideLeft) private var zoomSideLeft: Bool = true
    @AppStorage(UserDefaultsKeys.zoomSliderVisible) private var zoomSliderVisible: Bool = true

    // MARK: - Layout constants
    private let trackHeight: CGFloat = 220
    private let componentWidth: CGFloat = 52
    private let tickCount: Int = 32
    private let shortTickWidth: CGFloat = 14
    private let dotRightOffset: CGFloat = 18   // white dot distance from trailing edge
    private let opticalTickInset: CGFloat = 4  // extra gap between dot and its tick
    // Aligns indicator center with tick positions: rulerView padding(11) + canvas y-start(4) − half indicator height(10) = 5
    private let indicatorTickOffset: CGFloat = 5
    private let zoomYellow = Color(red: 1.0, green: 204.0 / 255.0, blue: 0.0)

    // MARK: - State
    @State private var isActivelyZooming: Bool = false
    @State private var showInitialLabel: Bool = true
    @State private var zoomIdleTask: Task<Void, Never>?
    @State private var lastHapticTick: Int?
    @State private var dragStartFactor: CGFloat = 1.0
    @State private var isDragging: Bool = false
    /// Drives the tick-elongation effect in `rulerView`. Animated 0→1 when zooming
    /// starts and 1→0 when the idle timer fires; the Canvas re-draws on every frame
    /// of both the gesture and the collapse animation.
    @State private var zoomActivityStrength: CGFloat = 0

    var body: some View {
        Group {
            if camera.isZoomSupported && camera.isSessionRunning && zoomSliderVisible {
                sliderBody
                    .scaleEffect(x: zoomSideLeft ? -1 : 1, y: 1)
                    .transition(
                        .move(edge: zoomSideLeft ? .leading : .trailing)
                        .combined(with: .opacity)
                    )
            }
        }
        .animation(.easeOut(duration: 0.4), value: camera.isZoomSupported && camera.isSessionRunning && zoomSliderVisible)
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run { showInitialLabel = false }
            }
        }
        .onChange(of: camera.zoomFactor) { _, newValue in
            isActivelyZooming = true
            withAnimation(.easeOut(duration: 0.12)) { zoomActivityStrength = 1.0 }
            triggerHapticIfNeeded(factor: newValue)
            zoomIdleTask?.cancel()
            zoomIdleTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                await MainActor.run { isActivelyZooming = false }
            }
        }
        // Collapse the tick-extension effect when zoom settles. Kept in a synchronous
        // onChange rather than inside the async Task so withAnimation is guaranteed to
        // run within SwiftUI's update cycle and actually interpolates the Canvas redraws.
        .onChange(of: isActivelyZooming) { _, isActive in
            guard !isActive else { return }
            withAnimation(.easeOut(duration: 0.5)) { zoomActivityStrength = 0.0 }
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
                .animation(isDragging ? nil : .easeOut(duration: 0.25), value: indicatorY)
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
                .onEnded { _ in
                    isDragging = false
                    camera.snapToNearestOpticalStop()
                }
        )
    }

    // MARK: - Ruler ticks

    private var rulerView: some View {
        let maxZoom = camera.maxZoomFactor
        let stops = camera.opticalZoomStops.filter { $0 > 1.0 }
        let currentFraction = fillFraction(for: camera.zoomFactor)

        return TickRulerCanvas(
            maxZoom: maxZoom,
            tickCount: tickCount,
            trackHeight: trackHeight,
            shortTickWidth: shortTickWidth,
            opticalTickInset: opticalTickInset,
            dotRightOffset: dotRightOffset,
            componentWidth: componentWidth,
            invertZoomDirection: invertZoomDirection,
            stops: stops,
            currentFraction: currentFraction,
            activityStrength: zoomActivityStrength
        )
    }

    // MARK: - Current zoom indicator

    private var currentZoomIndicator: some View {
        let showText = isActivelyZooming || showInitialLabel

        return HStack(spacing: 0) {
            Spacer(minLength: 0)

            if showText {
                Text(zoomLabel(for: camera.zoomFactor))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
                    .frame(width: 4, height: 4)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            // Hair-line connector to the ruler ticks — subtler when showing the dot.
            // Width switches between shortTickWidth (pill) and dotRightOffset (dot) so that
            // the dot center lands at the same x as the Canvas optical-stop dots.
            Color.white
                .frame(width: showText ? shortTickWidth : dotRightOffset - 2, height: showText ? 1.5 : 0.5)
                .opacity(showText ? 0.7 : 0.15)
        }
        .frame(width: componentWidth, height: 20)
        .animation(.easeOut(duration: 0.3), value: showText)
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

/// A dedicated canvas for drawing the tick marks in the zoom ruler.
///
/// This view is extracted from `ZoomSliderView` to explicitly conform to `Animatable`.
/// By exposing `currentFraction` and `activityStrength` as an `AnimatablePair`, SwiftUI
/// natively interpolates these properties during active animations like `.easeOut`. The Canvas
/// then evaluates continuously with these intermediate values, providing a fluid tick-bulge 
/// expansion during zoom, and a smooth retraction transition when zooming finishes natively.
private struct TickRulerCanvas: View, Animatable {
    var maxZoom: CGFloat
    var tickCount: Int
    var trackHeight: CGFloat
    var shortTickWidth: CGFloat
    var opticalTickInset: CGFloat
    var dotRightOffset: CGFloat
    var componentWidth: CGFloat
    var invertZoomDirection: Bool
    var stops: [CGFloat]

    /// The current relative progress (0.0 to 1.0) along the zoom range in log-space.
    /// This dictates where the tick-elongation "bulge" is vertically centered.
    var currentFraction: CGFloat

    /// The overall intensity of the tick expansion effect (0.0 to 1.0).
    /// Used to smoothly fade the expansion in and out without jumping when panning starts or stops.
    var activityStrength: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(currentFraction, activityStrength) }
        set {
            currentFraction = newValue.first
            activityStrength = newValue.second
        }
    }

    var body: some View {
        let logMax = log(maxZoom)
        // Half a tick's width in log-space — mirrors the log scale used by the indicator and drag gesture.
        let halfTickLog = maxZoom > 1.0 && logMax > 0 ? logMax / CGFloat(tickCount - 1) * 0.5 : 0

        Canvas { ctx, size in
            guard maxZoom > 1.0 else { return }
            let spacing = trackHeight / CGFloat(tickCount - 1)

            // Draw normal ticks
            for i in 0..<tickCount {
                let y = 4.0 + CGFloat(i) * spacing
                let t = CGFloat(i) / CGFloat(tickCount - 1)
                let tickLog = invertZoomDirection ? t * logMax : (1.0 - t) * logMax
                let tickFraction: CGFloat = invertZoomDirection ? t : (1.0 - t)

                let isMaxZoom = invertZoomDirection ? i == tickCount - 1 : i == 0
                let isMinZoom = invertZoomDirection ? i == 0 : i == tickCount - 1
                
                // If this is too close to an exact optical stop, suppress this generic tick entirely
                let isNearOpticalStop = stops.contains { abs(log(max($0, 1.0)) - tickLog) < halfTickLog * 1.5 }

                if isNearOpticalStop && !isMaxZoom && !isMinZoom { continue }

                // Gaussian falloff centered on the current zoom fraction
                let d = tickFraction - currentFraction
                let influence = exp(-d * d / (2 * 0.18 * 0.18)) * activityStrength
                let extraLength: CGFloat = influence * 8

                var line = Path()
                let x0 = size.width - shortTickWidth + opticalTickInset - extraLength
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))

                let tickColor: Color = isMaxZoom || isMinZoom ? .white.opacity(0.8) : .white.opacity(0.45)
                ctx.stroke(line, with: .color(tickColor), lineWidth: 0.5)

                if isMaxZoom || isMinZoom {
                    let dotSize: CGFloat = 4
                    let dotX = size.width - dotRightOffset - dotSize / 2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                        with: .color(.white.opacity(0.9))
                    )
                }
            }

            // Draw exact optical stops (white dots) at their precise continuous coordinate
            for stop in stops {
                let stopLog = log(max(stop, 1.0))
                // Skip if it's the bounding min or max since they're already drawn
                if stopLog <= 0.001 || abs(stopLog - logMax) < 0.001 { continue }
                
                let stopFraction = stopLog / logMax
                let exactT = invertZoomDirection ? stopFraction : (1.0 - stopFraction)
                let y = 4.0 + exactT * trackHeight

                let d = stopFraction - currentFraction
                let influence = exp(-d * d / (2 * 0.18 * 0.18)) * activityStrength
                let extraLength: CGFloat = influence * 8

                var line = Path()
                let x0 = size.width - shortTickWidth + opticalTickInset - extraLength
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))

                ctx.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 0.5)

                let dotSize: CGFloat = 4
                let dotX = size.width - dotRightOffset - dotSize / 2
                ctx.fill(
                    Path(ellipseIn: CGRect(x: dotX, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                    with: .color(.white.opacity(0.9))
                )
            }
        }
        .frame(width: componentWidth, height: trackHeight + 8)
    }
}
