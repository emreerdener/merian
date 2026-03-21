import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import SwiftData

struct CameraRootView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    @EnvironmentObject var vui: ViewfinderIntelligence
    @EnvironmentObject var photoLibraryManager: PhotoLibraryManager
    @EnvironmentObject var gamificationManager: GamificationManager
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var viewModel = CameraViewModel()
    
    @State private var focusLocation: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var focusTask: Task<Void, Never>? = nil
    
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Full-bleed camera feed
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
            
            
            CameraFocusIndicatorView(
                showFocusIndicator: showFocusIndicator,
                focusLocation: focusLocation
            )
            
            // Shutter Snap Animation
            Color.black
                .ignoresSafeArea()
                .opacity(viewModel.flashOpacity)
                .allowsHitTesting(false)
            
            // Thermal Warning Indicator overlay
            ThermalWarningOverlay()
            
            // Action Overlay Context
            if !viewModel.isAnalyzingFullscreen {
                // Extracted Shutter Button Overlay
                CameraControlsOverlayView(
                    latestThumbnail: photoLibraryManager.latestThumbnail,
                    isFlashEnabled: cameraManager.isFlashEnabled,
                    selectedPhotoItem: $viewModel.selectedPhotoItem,
                    activeSheet: $viewModel.activeSheet,
                    onCapture: { viewModel.executeCapture() },
                    onToggleFlash: { cameraManager.toggleFlash() }
                )
            }
            
            // Full-Screen Scanning Overlay
            if viewModel.isAnalyzingFullscreen, let uiImage = viewModel.analysisImage {
                ScanningOverlayView(uiImage: uiImage, scanningPhaseText: viewModel.scanningPhaseText)
                    .transition(.opacity)
                    .zIndex(10)
            }
            } // ZStack
        } // NavigationStack
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
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            viewModel.handlePhotoPickerSelection(newItem: newItem, modelContext: modelContext)
        }
        .fullScreenCover(item: $viewModel.imageToCrop) { identItem in
            ImageCropperView(
                image: identItem.image,
                onCrop: { croppedData in
                    viewModel.handleCropCompletion(croppedData: croppedData, modelContext: modelContext)
                },
                onCancel: {
                    viewModel.imageToCrop = nil
                }
            )
        }
        .sheet(isPresented: $gamificationManager.showTerrariumSheet, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            TerrariumView()
                .presentationDragIndicator(.hidden)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
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
        .preferredColorScheme(themeMode.colorScheme)
    }
}

@available(iOS 17.2, *)
struct HardwareCaptureInteraction: UIViewRepresentable {
    var isEnabled: Bool
    let action: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // Allow touches to pass safely through to the viewfinder
        
        let interaction = AVCaptureEventInteraction { event in
            // .began guarantees instant zero-latency capture mirroring the native Camera app
            if event.phase == .began {
                DispatchQueue.main.async {
                    action()
                }
            }
        }
        interaction.isEnabled = isEnabled
        view.addInteraction(interaction)
        
        context.coordinator.interaction = interaction
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.interaction?.isEnabled = isEnabled
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var interaction: AVCaptureEventInteraction?
    }
}

extension View {
    /// Natively binds the physical Volume, Action, and Camera Control buttons to the shutter action
    @ViewBuilder
    func onPhysicalCameraShutter(isEnabled: Bool, perform action: @escaping () -> Void) -> some View {
        if #available(iOS 17.2, *) {
            self.background(HardwareCaptureInteraction(isEnabled: isEnabled, action: action))
        } else {
            // iOS 17.0 and 17.1 gracefully fallback to the on-screen UI button safely
            self
        }
    }
}



