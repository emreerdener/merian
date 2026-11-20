import SwiftUI

/// Vertical zoom meter overlay for the camera viewfinder.
///
/// Displays a tick-mark ruler with optical stop indicators and a floating
/// zoom chip that tracks the current zoom factor. Zoom is controlled via
/// dragging the slider, or pinch/swipe gestures on the full viewfinder.
/// Self-contained: reads `CameraManager` from the environment and returns
/// `EmptyView` on hardware where zoom is not supported.
struct ZoomSliderView: View {
    let onOpticalStopTick: () -> Void
    let onRegularTick: () -> Void

    @Environment(CameraManager.self) private var camera
    @Environment(AppSettings.self) private var appSettings

    // MARK: - Layout constants
    private let trackHeight: CGFloat = 220
    private let componentWidth: CGFloat = 52
    private let tickCount: Int = 32
    private let shortTickWidth: CGFloat = 14
    private let dotRightOffset: CGFloat = 18
    private let settledDotRightOffset: CGFloat = 8
    private let opticalTickInset: CGFloat = 4  // extra gap between dot and its tick
    // Aligns indicator center with tick positions: rulerView padding(11) + canvas y-start(4) − half indicator height(10) = 5
    private let indicatorTickOffset: CGFloat = 5

    // MARK: - State
    @State private var isActivelyZooming: Bool = false
    @State private var zoomIdleTask: Task<Void, Never>?
    @State private var lastHapticTick: Int?
    @State private var dragStartFactor: CGFloat = 1.0
    @State private var isDragging: Bool = false
    /// Shared progress for tick length, dot inset, and the current zoom indicator.
    @State private var zoomActivityStrength: CGFloat = 0

    init(
        onOpticalStopTick: @escaping () -> Void = {},
        onRegularTick: @escaping () -> Void = {}
    ) {
        self.onOpticalStopTick = onOpticalStopTick
        self.onRegularTick = onRegularTick
    }

    var body: some View {
        Group {
            if isVisible {
                sliderBody
                    .scaleEffect(x: appSettings.zoomSideLeft ? -1 : 1, y: 1)
                    .transition(
                        .move(edge: appSettings.zoomSideLeft ? .leading : .trailing)
                        .combined(with: .opacity)
                    )
            }
        }
        .animation(.easeOut(duration: 0.4), value: isVisible)
        .onChange(of: camera.zoomFactor) { _, newValue in
            guard isVisible else { return }
            isActivelyZooming = true
            withAnimation(.easeOut(duration: 0.12)) { zoomActivityStrength = 1.0 }
            triggerHapticIfNeeded(factor: newValue)
            zoomIdleTask?.cancel()
            zoomIdleTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(0.8))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                isActivelyZooming = false
            }
        }
        // Apply the same settling transaction to both animatable renderers.
        .onChange(of: isActivelyZooming) { _, isActive in
            guard !isActive, isVisible else { return }
            withAnimation(.easeOut(duration: 0.5)) { zoomActivityStrength = 0.0 }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible { resetPresentation() }
        }
        .onDisappear(perform: resetPresentation)
    }

    private var isVisible: Bool {
        camera.isZoomSupported && camera.isSessionRunning && appSettings.zoomSliderVisible
    }

    private func resetPresentation() {
        zoomIdleTask?.cancel()
        zoomIdleTask = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isActivelyZooming = false
            zoomActivityStrength = 0
            isDragging = false
        }
    }

    // MARK: - Meter body

    private var sliderBody: some View {
        let fraction = fillFraction(for: camera.zoomFactor)
        // Default: top = max zoom, bottom = 1×. Inverted: top = 1×, bottom = max zoom.
        let indicatorY = indicatorTickOffset + (appSettings.invertZoomDirection ? fraction * trackHeight : (1.0 - fraction) * trackHeight)

        return ZStack(alignment: .top) {
            rulerView
                .padding(.top, 11)
            currentZoomIndicator
                .animation(isDragging ? nil : .easeOut(duration: 0.25)) { indicator in
                    indicator.offset(y: indicatorY)
                }
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
                    let dy = appSettings.invertZoomDirection ? value.translation.height : -value.translation.height
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
            settledDotRightOffset: settledDotRightOffset,
            componentWidth: componentWidth,
            invertZoomDirection: appSettings.invertZoomDirection,
            stops: stops,
            currentFraction: currentFraction,
            activityStrength: zoomActivityStrength
        )
    }

    // MARK: - Current zoom indicator

    private var currentZoomIndicator: some View {
        ZoomActivityIndicator(
            label: zoomLabel(for: camera.zoomFactor),
            mirrored: appSettings.zoomSideLeft,
            componentWidth: componentWidth,
            connectorWidth: shortTickWidth,
            dotRightOffset: dotRightOffset,
            settledDotRightOffset: settledDotRightOffset,
            activityStrength: zoomActivityStrength
        )
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
            onOpticalStopTick()
        } else {
            onRegularTick()
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

/// Interpolates indicator geometry with the same progress as the ruler Canvas.
private struct ZoomActivityIndicator: View, Animatable {
    var label: String
    var mirrored: Bool
    var componentWidth: CGFloat
    var connectorWidth: CGFloat
    var dotRightOffset: CGFloat
    var settledDotRightOffset: CGFloat
    var activityStrength: CGFloat

    var animatableData: CGFloat {
        get { activityStrength }
        set { activityStrength = newValue }
    }

    var body: some View {
        let progress = min(max(activityStrength, 0), 1)
        let dotInset = settledDotRightOffset + (dotRightOffset - settledDotRightOffset) * progress
        let yellow = Color(red: 1.0, green: 204.0 / 255.0, blue: 0.0)

        ZStack(alignment: .trailing) {
            Circle()
                .fill(yellow)
                .frame(width: 4, height: 4)
                .opacity(1 - progress)
                .padding(.trailing, dotInset - 2)

            if progress > 0 {
                Color.white
                    .frame(width: connectorWidth * progress, height: 1.5)
                    .opacity(0.7 * progress)
                    .transition(.identity)

                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .contentTransition(.numericText())
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(yellow))
                    .fixedSize()
                    .scaleEffect(0.7 + 0.3 * progress, anchor: .trailing)
                    .opacity(progress)
                    .padding(.trailing, (settledDotRightOffset - 2) * (1 - progress) + connectorWidth * progress)
                    .transition(.identity)
            }
        }
        .frame(width: componentWidth, height: 20, alignment: .trailing)
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
    var settledDotRightOffset: CGFloat
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
            let progress = min(max(activityStrength, 0), 1)
            let dotInset = settledDotRightOffset + (dotRightOffset - settledDotRightOffset) * progress

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
                let influence = exp(-d * d / (2 * 0.18 * 0.18)) * progress
                let extraLength: CGFloat = influence * 8

                var line = Path()
                let x0 = size.width - (shortTickWidth - opticalTickInset) * progress - extraLength
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))

                let tickColor: Color = isMaxZoom || isMinZoom ? .white.opacity(0.8) : .white.opacity(0.45)
                if progress > 0 {
                    ctx.stroke(line, with: .color(tickColor), lineWidth: 0.5)
                }

                if isMaxZoom || isMinZoom {
                    let dotSize: CGFloat = 4
                    let dotX = size.width - dotInset - dotSize / 2
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
                let influence = exp(-d * d / (2 * 0.18 * 0.18)) * progress
                let extraLength: CGFloat = influence * 8

                var line = Path()
                let x0 = size.width - (shortTickWidth - opticalTickInset) * progress - extraLength
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))

                if progress > 0 {
                    ctx.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 0.5)
                }

                let dotSize: CGFloat = 4
                let dotX = size.width - dotInset - dotSize / 2
                ctx.fill(
                    Path(ellipseIn: CGRect(x: dotX, y: y - dotSize / 2, width: dotSize, height: dotSize)),
                    with: .color(.white.opacity(0.9))
                )
            }
        }
        .frame(width: componentWidth, height: trackHeight + 8)
    }
}
