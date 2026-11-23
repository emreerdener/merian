import SwiftUI

struct VisualCaptureView: View {
    let viewModel: CaptureWorkspaceViewModel
    var isCameraVisible: Bool = false
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
                cameraManager: cameraManager,
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
                isCameraVisible: isCameraVisible,
                hasEmptyDraft: viewModel.stagedCapture.isEmpty && viewModel.descriptionDraft.isEmpty,
                isCapturing: viewModel.isCapturing || viewModel.isPreparingVideo
                    || viewModel.isCheckingScanAdmission || viewModel.isQueueingStagedCapture,
                claimIntroduction: viewModel.dependencies.claimViewfinderIntroduction,
                activeScanImages: viewModel.stagedCapture.images.map(\.uiImage)
                    + viewModel.stagedCapture.videos.compactMap { $0.coverImage?.uiImage },
                isRefining: viewModel.baseRefinementContext != nil,
                isVideoRecording: viewModel.isVideoRecording,
                videoRecordingProgress: viewModel.videoRecordingProgress,
                showsViewfinderHints: viewModel.shouldShowViewfinderHints,
                onZoomOpticalStopTick: {
                    viewModel.triggerZoomOpticalStopFeedback()
                },
                onZoomRegularTick: {
                    viewModel.triggerZoomTickFeedback()
                }
            )
        }
        .onDisappear {
            focusHideTask?.cancel()
            focusHideTask = nil
        }
    }
}

// MARK: - Camera Controls Layer
private struct CameraControlsLayer: View {
    let isCameraVisible: Bool
    let hasEmptyDraft: Bool
    let isCapturing: Bool
    let claimIntroduction: @MainActor () -> Bool
    let activeScanImages: [UIImage]
    var isRefining: Bool = false
    var isVideoRecording: Bool = false
    var videoRecordingProgress: Double = 0
    var showsViewfinderHints: Bool = true
    let onZoomOpticalStopTick: () -> Void
    let onZoomRegularTick: () -> Void

    var body: some View {
        MainOverlayView(
            isCameraVisible: isCameraVisible,
            hasEmptyDraft: hasEmptyDraft,
            isCapturing: isCapturing,
            claimIntroduction: claimIntroduction,
            activeScanImages: activeScanImages,
            isRefining: isRefining,
            isVideoRecording: isVideoRecording,
            videoRecordingProgress: videoRecordingProgress,
            showsViewfinderHints: showsViewfinderHints,
            onZoomOpticalStopTick: onZoomOpticalStopTick,
            onZoomRegularTick: onZoomRegularTick
        )
    }
}

#if targetEnvironment(simulator)
private struct SimulatorCameraSurfaceView: UIViewRepresentable {
    let onTap: (CGPoint, CGPoint) -> Void
    let onVerticalDragActiveChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SimulatorCameraSurfaceView

        init(_ parent: SimulatorCameraSurfaceView) { self.parent = parent }

        // Match the camera bridge's directional pan arbitration without starting
        // camera hardware. A zero-distance SwiftUI drag consumed horizontal paging.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        @objc func tap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view else { return }
            let location = sender.location(in: view)
            let devicePoint = CGPoint(
                x: min(max(location.x / max(view.bounds.width, 1), 0), 1),
                y: min(max(location.y / max(view.bounds.height, 1), 0), 1)
            )
            parent.onTap(location, devicePoint)
        }

        @objc func pan(_ sender: UIPanGestureRecognizer) {
            switch sender.state {
            case .began: parent.onVerticalDragActiveChanged?(true)
            case .ended, .cancelled, .failed: parent.onVerticalDragActiveChanged?(false)
            default: break
            }
        }
    }
}
#endif
