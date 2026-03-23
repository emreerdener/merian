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

    // MARK: - View Hierarchy
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. Optical Bridge (Underlay Black Safely)
                CameraPreviewView(
                    session: cameraManager.session,
                    onTap: { _, devicePoint in
                        viewModel.handleFocusTap(devicePoint: devicePoint)
                    }
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
                .modifier(FocusTapGestureModifier(onTap: { _ in }))
                
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
        .onChange(of: viewModel.isAnalyzingFullscreen) { _, isFullscreen in
            viewModel.synchronizeAnalysisState(isFullscreen: isFullscreen)
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

