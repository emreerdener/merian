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
    
    // MARK: - Focus Interactions
    @State private var focusLocation: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var focusTask: Task<Void, Never>? = nil

    // MARK: - View Hierarchy
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Optical Bridge
                CameraPreviewView(
                    session: cameraManager.session,
                    onTap: { layerPoint, devicePoint in
                        viewModel.handleFocusTap(devicePoint: devicePoint)
                        focusLocation = layerPoint
                        showFocusIndicator = true
                        
                        focusTask?.cancel()
                        focusTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if !Task.isCancelled {
                                withAnimation(.easeOut) {
                                    showFocusIndicator = false
                                }
                            }
                        }
                    }
                )
                .ignoresSafeArea()
                
                FocusIndicator(
                    showFocusIndicator: showFocusIndicator,
                    focusLocation: focusLocation
                )
            
                // MARK: - Hardware Effects
                // Shutter Snap Animation
                Color.black
                    .ignoresSafeArea()
                    .opacity(viewModel.flashOpacity)
                    .allowsHitTesting(false)
                
                // Thermal Warning Indicator overlay
                ThermalWarningView()
                
                // MARK: - Interface Overlays
                if !viewModel.isAnalyzingFullscreen {
                // Extracted Shutter Button Overlay
                MainOverlayView(
                    latestThumbnail: photoLibraryManager.latestThumbnail,
                    isFlashEnabled: cameraManager.isFlashEnabled,
                    selectedPhotoItems: $viewModel.selectedPhotoItems,
                    activeSheet: $viewModel.activeSheet,
                    activeScanImages: viewModel.activeScanImages,
                    onCapture: { viewModel.executeCapture() },
                    onToggleFlash: { cameraManager.toggleFlash() },
                    onThumbnailTap: { index in
                        viewModel.presentCrop(for: index)
                    },
                    onSubmitScan: { viewModel.submitActiveScan(modelContext: modelContext) },
                    onCancelScan: {
                        viewModel.activeScanImages.removeAll()
                        viewModel.activeScannedDatas.removeAll()
                        viewModel.activeOriginals.removeAll()
                    }
                )
            }
            
            // Full-Screen Scanning Overlay
            if viewModel.isAnalyzingFullscreen, !viewModel.analysisImages.isEmpty {
                ScanningOverlayView(images: viewModel.analysisImages, scanningPhaseText: viewModel.scanningPhaseText)
                    .transition(.opacity)
                    .zIndex(10)
            }
            } // ZStack
        } // NavigationStack
        
        // MARK: - View Modifiers
        // Unified Application Sheet Router Overlay
        .cameraSheetRouter(viewModel: viewModel)
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
        .fullScreenCover(item: $viewModel.imageToCrop) { identItem in
            ImageCropperView(
                image: identItem.image,
                initialScale: identItem.lastCropScale,
                initialOffset: identItem.lastCropOffset,
                onCrop: { croppedData, finalScale, finalOffset in
                    if let editIndex = viewModel.editingCropIndex, editIndex < viewModel.activeScannedDatas.count {
                        viewModel.activeScannedDatas[editIndex] = croppedData
                        if let updatedThumb = UIImage(data: croppedData) {
                            viewModel.activeScanImages[editIndex] = updatedThumb
                        }
                        viewModel.activeOriginals[editIndex].lastCropScale = finalScale
                        viewModel.activeOriginals[editIndex].lastCropOffset = finalOffset
                    }
                    viewModel.editingCropIndex = nil
                    viewModel.imageToCrop = nil
                },
                onCancel: {
                    viewModel.editingCropIndex = nil
                    viewModel.imageToCrop = nil
                },
                onDelete: {
                    if let editIndex = viewModel.editingCropIndex, editIndex < viewModel.activeScannedDatas.count {
                        viewModel.activeScannedDatas.remove(at: editIndex)
                        viewModel.activeScanImages.remove(at: editIndex)
                        viewModel.activeOriginals.remove(at: editIndex)
                    }
                    viewModel.editingCropIndex = nil
                    viewModel.imageToCrop = nil
                }
            )
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

