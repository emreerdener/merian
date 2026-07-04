import SwiftUI

struct VisualCaptureView: View {
    let viewModel: CaptureWorkspaceViewModel
    @Binding var isVerticalZooming: Bool
    
    @Environment(CameraManager.self) private var cameraManager
    
    // MARK: - Focus Indicator State
    @State private var focusLocation: CGPoint?
    @State private var showFocusIndicator: Bool = false
    @State private var focusHideTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // 1. Optical Bridge
            #if targetEnvironment(simulator)
            SimulatorCameraSurfaceView(
                onTap: { layerPoint, devicePoint in
                    viewModel.handleFocusTap(devicePoint: devicePoint)
                    focusLocation = layerPoint
                    showFocusIndicator = true
                    focusHideTask?.cancel()
                    focusHideTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut) { showFocusIndicator = false }
                    }
                },
                onVerticalDragActiveChanged: { isVerticalZooming = $0 }
            )
            .overlay { FocusIndicator(showFocusIndicator: showFocusIndicator, focusLocation: focusLocation) }
            #else
            CameraPreviewView(
                session: cameraManager.session,
                onTap: { layerPoint, devicePoint in
                    viewModel.handleFocusTap(devicePoint: devicePoint)
                    
                    // Drive the focus indicator from the UIKit layer point — the SwiftUI
                    // gesture modifier can't compete with the UITapGestureRecognizer on
                    // the preview layer.
                    focusLocation = layerPoint
                    showFocusIndicator = true
                    focusHideTask?.cancel()
                    focusHideTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut) { showFocusIndicator = false }
                    }
                },
                onVerticalDragActiveChanged: { isVerticalZooming = $0 }
            )
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .overlay { FocusIndicator(showFocusIndicator: showFocusIndicator, focusLocation: focusLocation) }
            #endif

            // 2. Hardware Effects (Flash Snap)
            Color.black
                .ignoresSafeArea()
                .opacity(viewModel.flashOpacity)
                .allowsHitTesting(false)

            // 3. Thermal Overlay
            ThermalWarningView()

            // 4. ViewfinderHints + ZoomSlider (scroll-dependent; stays in page)
            CameraControlsLayer(
                activeScanImages: viewModel.stagedCapture.images.map(\.uiImage)
                    + viewModel.stagedCapture.videos.compactMap { $0.coverImage?.uiImage },
                isRefining: viewModel.baseRefinementContext != nil,
                isVideoRecording: viewModel.isVideoRecording,
                videoRecordingProgress: viewModel.videoRecordingProgress,
                showsViewfinderHints: viewModel.shouldShowViewfinderHints
            )
        }
    }
}

// MARK: - Camera Controls Layer
private struct CameraControlsLayer: View {
    let activeScanImages: [UIImage]
    var isRefining: Bool = false
    var isVideoRecording: Bool = false
    var videoRecordingProgress: Double = 0
    var showsViewfinderHints: Bool = true

    var body: some View {
        MainOverlayView(
            activeScanImages: activeScanImages,
            isRefining: isRefining,
            isVideoRecording: isVideoRecording,
            videoRecordingProgress: videoRecordingProgress,
            showsViewfinderHints: showsViewfinderHints
        )
    }
}

#if targetEnvironment(simulator)
private struct SimulatorCameraSurfaceView: View {
    let onTap: (CGPoint, CGPoint) -> Void
    let onVerticalDragActiveChanged: ((Bool) -> Void)?

    @State private var verticalDragActive = false

    var body: some View {
        GeometryReader { proxy in
            Color.black
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let isTapCandidate = abs(value.translation.width) < 8 && abs(value.translation.height) < 8
                            guard !isTapCandidate else { return }

                            let isVertical = abs(value.translation.height) > abs(value.translation.width)
                            guard isVertical, !verticalDragActive else { return }
                            verticalDragActive = true
                            onVerticalDragActiveChanged?(true)
                        }
                        .onEnded { value in
                            defer {
                                if verticalDragActive {
                                    verticalDragActive = false
                                    onVerticalDragActiveChanged?(false)
                                }
                            }

                            let isTap = abs(value.translation.width) < 8 && abs(value.translation.height) < 8
                            guard isTap else { return }

                            let location = value.startLocation
                            let devicePoint = CGPoint(
                                x: min(max(location.x / max(proxy.size.width, 1), 0), 1),
                                y: min(max(location.y / max(proxy.size.height, 1), 0), 1)
                            )
                            onTap(location, devicePoint)
                        }
                )
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
    }
}
#endif
