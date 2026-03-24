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

    // MARK: - Focus Indicator State
    @State private var focusLocation: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var focusHideTask: Task<Void, Never>? = nil

    // MARK: - View Hierarchy
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. Optical Bridge (Underlay Black Safely)
                CameraPreviewView(
                    session: cameraManager.session,
                    onTap: { layerPoint, devicePoint in
                        viewModel.handleFocusTap(devicePoint: devicePoint)

                        // Drive the focus indicator from the UIKit layer point — the SwiftUI gesture
                        // modifier can't compete with the UITapGestureRecognizer on the preview layer.
                        focusLocation = layerPoint
                        showFocusIndicator = true
                        focusHideTask?.cancel()
                        focusHideTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut) { showFocusIndicator = false }
                        }
                    }
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
                
                // 4. UI Interface Layer
                ZStack {
                    CameraControlsLayer(
                        latestThumbnail: photoLibraryManager.latestThumbnail,
                        isFlashEnabled: cameraManager.isFlashEnabled,
                        isTooltipVisible: viewModel.isTooltipVisible,
                        selectedPhotoItems: $viewModel.selectedPhotoItems,
                        activeSheet: $viewModel.activeSheet,
                        activeScanImages: viewModel.activeScanImages,
                        isAnalyzingFullscreen: viewModel.isAnalyzingFullscreen,
                        onCapture: { viewModel.executeCapture() },
                        onToggleFlash: { cameraManager.toggleFlash() },
                        onThumbnailTap: { index in viewModel.presentCrop(for: index) },
                        onSubmitScan: { viewModel.submitActiveScan(modelContext: modelContext) },
                        onCancelScan: {
                            viewModel.activeScanImages.removeAll()
                            viewModel.activeScannedDatas.removeAll()
                            viewModel.activeOriginals.removeAll()
                        },
                        onModeChange: {
                            Task {
                                await viewModel.scheduleTooltipDismissal()
                            }
                        }
                    )
                    
                    if viewModel.isAnalyzingFullscreen, !viewModel.analysisImages.isEmpty {
                        ScanningOverlayView(images: viewModel.analysisImages, scanningPhaseText: viewModel.scanningPhaseText)
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }
            } // ZStack
        } // NavigationStack
        
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
        .onChange(of: viewModel.isAnalyzingFullscreen) { _, isFullscreen in
            viewModel.synchronizeAnalysisState(isFullscreen: isFullscreen)
            if isFullscreen {
                cameraManager.stopSession()
            } else {
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

private struct CameraControlsLayer: View {
    let latestThumbnail: UIImage?
    let isFlashEnabled: Bool
    let isTooltipVisible: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var activeSheet: CameraViewModel.ActiveSheet?
    let activeScanImages: [UIImage]
    let isAnalyzingFullscreen: Bool
    
    let onCapture: () -> Void
    let onToggleFlash: () -> Void
    let onThumbnailTap: (Int) -> Void
    let onSubmitScan: () -> Void
    let onCancelScan: () -> Void
    let onModeChange: () -> Void
    
    var body: some View {
        if !isAnalyzingFullscreen {
            MainOverlayView(
                latestThumbnail: latestThumbnail,
                isFlashEnabled: isFlashEnabled,
                isTooltipVisible: isTooltipVisible,
                selectedPhotoItems: $selectedPhotoItems,
                activeSheet: $activeSheet,
                activeScanImages: activeScanImages,
                onCapture: onCapture,
                onToggleFlash: onToggleFlash,
                onThumbnailTap: onThumbnailTap,
                onSubmitScan: onSubmitScan,
                onCancelScan: onCancelScan,
                onModeChange: onModeChange
            )
        }
    }
}

