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

            // 2. Hardware Effects (Flash Snap)
            Color.black
                .ignoresSafeArea()
                .opacity(viewModel.flashOpacity)
                .allowsHitTesting(false)

            // 3. Thermal Overlay
            ThermalWarningView()

            // 4. ViewfinderHints + ZoomSlider (scroll-dependent; stays in page)
            CameraControlsLayer(
                activeScanImages: viewModel.stagedCapture.images.map(\.uiImage),
                isRefining: viewModel.baseRefinementRecord != nil
            )
        }
    }
}

// MARK: - Camera Controls Layer
private struct CameraControlsLayer: View {
    let activeScanImages: [UIImage]
    var isRefining: Bool = false

    var body: some View {
        MainOverlayView(activeScanImages: activeScanImages, isRefining: isRefining)
    }
}
