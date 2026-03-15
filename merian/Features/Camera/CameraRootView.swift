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

    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Full-bleed camera feed
            CameraPreviewView(
                session: cameraManager.session,
                onTap: { layerPoint, devicePoint in
                    viewModel.handleFocusTap(layerPoint: layerPoint, devicePoint: devicePoint)
                }
            )
            .ignoresSafeArea()
            
            if viewModel.showFocusIndicator, let location = viewModel.focusLocation {
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                    .position(x: location.x, y: location.y)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: location)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            
            // Shutter Snap Animation
            Color.black
                .ignoresSafeArea()
                .opacity(viewModel.flashOpacity)
            
            // Thermal Warning Indicator overlay
            ThermalWarningOverlay()
            
            // Action Overlay Context
            if !viewModel.isAnalyzingFullscreen {
                ZStack {
                    VStack {
                        // Top Toolbar (Flash & Photos)
                        TopToolbarView(selectedPhotoItem: $viewModel.selectedPhotoItem)
                        Spacer()
                    }
                    
                    VStack {
                        // Viewfinder Intelligence Hint Banner
                        ViewfinderHintBanner()
                        Spacer()
                    }
                }
                .cameraNavigationToolbar(
                    isLifeListOpen: $viewModel.isLifeListOpen,
                    isUserProfileOpen: $viewModel.isUserProfileOpen,
                    isAnalyzingFullscreen: viewModel.isAnalyzingFullscreen
                )
                
                // Extracted Shutter Button Overlay
                VStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 1)
                            .frame(width: 72, height: 72)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                    }
                    // .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .onTapGesture {
                        viewModel.executeCapture()
                    }
                    .padding(.bottom, 10) // Pad natively to perfectly align bottom-edge with Toolbar constraints
                }
            }
            
            // Full-Screen Scanning Overlay
            if viewModel.isAnalyzingFullscreen, let uiImage = viewModel.analysisImage {
                ScanningOverlayView(uiImage: uiImage, scanningPhaseText: viewModel.scanningPhaseText)
                    .transition(.opacity)
                    .zIndex(10)
            }
            }
        }
        // Insight Data View overlay 
        .sheet(isPresented: $viewModel.isInsightSheetOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            InsightSheetView(isPresented: $viewModel.isInsightSheetOpen)
                .presentationDragIndicator(.hidden)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
        }
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
        .sheet(isPresented: $viewModel.isPaywallOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            PaywallView()
                .presentationDragIndicator(.hidden)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
        }
        .sheet(isPresented: $viewModel.isUserProfileOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            UserProfileView()
                .presentationDragIndicator(.hidden)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
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
        .sheet(isPresented: $viewModel.isLifeListOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            LifeListSearchView(isInsightSheetOpen: $viewModel.isInsightSheetOpen)
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
            isEnabled: !viewModel.isInsightSheetOpen &&
                       !viewModel.isLifeListOpen &&
                       !viewModel.isPaywallOpen &&
                       !viewModel.isUserProfileOpen &&
                       !viewModel.isAnalyzingFullscreen &&
                       viewModel.imageToCrop == nil
        ) {
            viewModel.executeCapture()
        }
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



