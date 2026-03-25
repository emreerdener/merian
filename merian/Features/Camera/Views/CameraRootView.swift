import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import SwiftData

struct CameraRootView: View {
    // MARK: - Environment & Dependencies
    @Environment(CameraManager.self) var cameraManager
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(ViewfinderIntelligence.self) var vui
    @Environment(PhotoLibraryManager.self) var photoLibraryManager
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) private var modelContext

    // MARK: - View Model & State
    @State private var viewModel = CameraViewModel()
    @State private var captureMode: CaptureMode = .visual
    @AppStorage("multiImageScanMode") private var multiImageScanMode: Bool = false

    // MARK: - Focus Indicator State
    @State private var focusLocation: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var focusHideTask: Task<Void, Never>? = nil

    // MARK: - Zoom Drag Lock
    @State private var isVerticalZooming: Bool = false

    /// Bridges CaptureMode into the optional Binding<ID?> form that scrollPosition(id:) requires.
    /// Wraps the setter in withAnimation so the MediaModeToggle pill animates when the page settles.
    private var captureModeScrollBinding: Binding<CaptureMode?> {
        Binding(
            get: { captureMode },
            set: { if let val = $0 { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { captureMode = val } } }
        )
    }

    // MARK: - View Hierarchy
    var body: some View {
        ZStack {
                // Paged capture mode switcher.
                // CameraPreviewView lives inside page 1 so the outer horizontal UIScrollView
                // naturally defers vertical pan gestures to the inner camera pan recognizer
                // (zoom), while claiming horizontal ones (paging).
                // GeometryReader captures the true full-screen dimensions (after the outer
                // ZStack's .ignoresSafeArea() expands it) and hands them to each page via
                // explicit .frame(), bypassing any ambiguity in containerRelativeFrame's
                // safe-area-vs-full-screen reference resolution.
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {

                            // MARK: Page 1 — Camera
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
                                    activeScanImages: viewModel.activeScanImages,
                                    isAnalyzingFullscreen: viewModel.isAnalyzingFullscreen
                                )
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(CaptureMode.visual)

                            // MARK: Page 2 — Audio Recording
                            AudioRecordingView()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(CaptureMode.audio)
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: captureModeScrollBinding)
                    .scrollDisabled(isVerticalZooming)
                    .background(ScrollBounceDisabler())
                }
                .ignoresSafeArea()

                // MARK: Fixed Overlay — Mode Toggle (top)
                if viewModel.activeScanImages.count < 2 {
                    VStack {
                        MediaModeToggle(activeMode: $captureMode, onModeChange: {})
                            .padding(.top, 16)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.activeScanImages.count)
                }

                // MARK: Fixed Overlay — Capture Controls + Navigation (bottom)
                VStack {
                    Spacer()

                    // Capture bar: library · shutter/record · flash
                    if viewModel.activeScanImages.count < 2 {
                        HStack(alignment: .bottom) {
                            PhotoLibraryButton(
                                selectedPhotoItems: $viewModel.selectedPhotoItems,
                                latestThumbnail: photoLibraryManager.latestThumbnail,
                                maxSelectionCount: multiImageScanMode ? max(1, 2 - viewModel.activeScanImages.count) : 1
                            )
                            .opacity(captureMode == .visual ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: captureMode)

                            Spacer()

                            CaptureButton(captureMode: captureMode, onCapture: { viewModel.executeCapture() })

                            Spacer()

                            FlashButton(
                                isFlashEnabled: cameraManager.isFlashEnabled,
                                onToggleFlash: { cameraManager.toggleFlash() }
                            )
                            .opacity(captureMode == .visual ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: captureMode)
                        }
                        .padding(.bottom, 48)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Navigation / scan toolbar
                    if viewModel.activeScanImages.isEmpty {
                        MainTabBar(
                            isScansOpen: $viewModel.activeSheet.mapped(to: .scans),
                            isUserProfileOpen: $viewModel.activeSheet.mapped(to: .profile)
                        )
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        ActiveScanToolbar(
                            images: viewModel.activeScanImages,
                            selectedPhotoItems: $viewModel.selectedPhotoItems,
                            onThumbnailTap: { index in viewModel.presentCrop(for: index) },
                            onCancel: {
                                viewModel.activeScanImages.removeAll()
                                viewModel.activeScannedDatas.removeAll()
                                viewModel.activeOriginals.removeAll()
                            },
                            onSubmit: { viewModel.submitActiveScan(modelContext: modelContext) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.activeScanImages.count)

                // Scanning overlay — above the pager and fixed controls.
                if viewModel.isAnalyzingFullscreen, !viewModel.analysisImages.isEmpty {
                    ScanningOverlayView(images: viewModel.analysisImages, scanningPhaseText: viewModel.scanningPhaseText)
                        .transition(.opacity)
                        .zIndex(10)
                }
        } // ZStack
        .background(Color.black.ignoresSafeArea())

        // MARK: - View Modifiers
        .cameraSheetRouter(viewModel: viewModel)
        .modifier(CropSheetModifier(
            isPresented: Binding(
                get: { viewModel.imageToCrop != nil },
                set: { if !$0 { viewModel.imageToCrop = nil } }
            ),
            viewModel: viewModel
        ))
        .onAppear {
            cameraManager.startSession()
            photoLibraryManager.startObservingAndFetch()
            AppDIContainer.shared.environmentContextManager.validatePermissions()
            AppDIContainer.shared.environmentContextManager.startLiveLocationTracking()
        }
        .onDisappear {
            cameraManager.stopSession()
            AppDIContainer.shared.environmentContextManager.stopLiveLocationTracking()
        }
        .onChange(of: viewModel.selectedPhotoItems) { _, newItems in
            viewModel.handlePhotoPickerSelection(newItems: newItems, modelContext: modelContext)
        }
        .onChange(of: viewModel.activeScanImages.count) { _, count in
            guard count == 1,
                  !UserDefaults.standard.bool(forKey: "multiImageScanMode") else { return }
            viewModel.submitActiveScan(modelContext: modelContext)
        }
        .onChange(of: captureMode) { _, newMode in
            if newMode == .audio {
                cameraManager.stopSession()
            } else if !viewModel.isAnalyzingFullscreen {
                cameraManager.startSession()
            }
        }
        .onChange(of: viewModel.isAnalyzingFullscreen) { _, isFullscreen in
            viewModel.synchronizeAnalysisState(isFullscreen: isFullscreen)
            if isFullscreen {
                cameraManager.stopSession()
            } else if captureMode == .visual {
                cameraManager.startSession()
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            viewModel.handleInferenceProcessingChange(isStillProcessing: isStillProcessing)
        }
        .onPhysicalCameraShutter(
            isEnabled: viewModel.activeSheet == nil &&
                       !viewModel.isAnalyzingFullscreen &&
                       viewModel.imageToCrop == nil
        ) {
            viewModel.executeCapture()
        }
    }
}

// MARK: - Camera Controls Layer
// Passes only scroll-dependent, camera-specific content into page 1.
// All persistent controls (toggle, capture bar, tab bar) live in the fixed overlay above.

private struct CameraControlsLayer: View {
    let activeScanImages: [UIImage]
    let isAnalyzingFullscreen: Bool

    var body: some View {
        if !isAnalyzingFullscreen {
            MainOverlayView(activeScanImages: activeScanImages)
        }
    }
}

// MARK: - Scroll Bounce Disabler
// SwiftUI has no native API for disabling pager bounce. This probe walks up the UIKit
// hierarchy from inside the ScrollView's content to find the backing UIScrollView
// and hard-disables bounce so neither edge rubber-bands.

private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { _ProbeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _ProbeView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            DispatchQueue.main.async { [weak self] in
                var current: UIView? = self?.superview
                while let view = current {
                    if let sv = view as? UIScrollView {
                        sv.bounces = false
                        return
                    }
                    current = view.superview
                }
            }
        }
    }
}

// MARK: - Capture Button
// Single button that transitions between the white shutter style (camera) and
// the red record style (audio) in place, with no position change.

private struct CaptureButton: View {
    let captureMode: CaptureMode
    let onCapture: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: 80, height: 80)

            Circle()
                .fill(captureMode == .audio ? Color.red : Color.white)
                .frame(width: 72, height: 72)
                .animation(.easeInOut(duration: 0.25), value: captureMode)
        }
        .environment(\.colorScheme, .dark)
        .onTapGesture {
            guard captureMode == .visual else { return }
            HapticManager.shared.triggerFocusSnap()
            onCapture()
        }
    }
}
