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
        ZStack {
            // Full-bleed camera feed
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            // Shutter Snap Animation
            Color.black
                .ignoresSafeArea()
                .opacity(viewModel.flashOpacity)
            
            // Thermal Warning Indicator overlay
            if hardwareOrchestrator.isCriticalHeatWarningActive {
                VStack {
                    Text("DEVICE CRITICAL HEAT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                    Spacer()
                }
                .padding(.top, 40)
            }
            
            // Action Overlay Context
            if !viewModel.isAnalyzingFullscreen {
                VStack {
                    // Top Toolbar (Flash & Photos)
                    HStack(alignment: .top) {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            GlassCircularButton(
                                iconName: cameraManager.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill",
                                iconColor: cameraManager.isFlashEnabled ? .yellow : .white
                            ) {
                                cameraManager.toggleFlash()
                            }
                            
                            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                ZStack {
                                    if hardwareOrchestrator.isGlassmorphismEnabled {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .environment(\.colorScheme, .dark)
                                            .frame(width: 50, height: 50)
                                    } else {
                                        Circle()
                                            .fill(Color.black.opacity(0.7))
                                            .frame(width: 50, height: 50)
                                    }
                                    
                                    if let thumbnail = photoLibraryManager.latestThumbnail {
                                        Image(uiImage: thumbnail)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 46, height: 46)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    
                    Spacer()
                    
                    // Viewfinder Intelligence Hint Banner
                    if !vui.isOptimal {
                        Text(vui.currentHint.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .clipShape(Capsule())
                            .padding(.bottom, 16)
                    }
                    
                    // Floating Action Bar Interface
                    MerianActionBar(
                        isLifeListOpen: $viewModel.isLifeListOpen,
                        isPaywallOpen: $viewModel.isPaywallOpen,
                        isInsightSheetOpen: $viewModel.isInsightSheetOpen,
                        isAnalyzingFullscreen: $viewModel.isAnalyzingFullscreen,
                        isUserProfileOpen: $viewModel.isUserProfileOpen,
                        imageToCrop: $viewModel.imageToCrop,
                        onCaptureTriggered: viewModel.executeCapture
                    )
                }
            }
            
            // Full-Screen Scanning Overlay
            if viewModel.isAnalyzingFullscreen, let uiImage = viewModel.analysisImage {
                ZStack {
                    // Base darkening layer
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                    
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                        .padding(.horizontal, 32)
                    
                    VStack {
                        Spacer()
                        Text(viewModel.scanningPhaseText)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .clipShape(Capsule())
                            .padding(.bottom, 60)
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        // Insight Data View overlay 
        .sheet(isPresented: $viewModel.isInsightSheetOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            InsightSheetView(isPresented: $viewModel.isInsightSheetOpen)
                .presentationDragIndicator(.visible)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
        }
        .onAppear {
            cameraManager.startSession()
            photoLibraryManager.startObservingAndFetch()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            viewModel.handlePhotoPickerSelection(newItem: newItem, modelContext: modelContext)
        }
        .sheet(isPresented: $viewModel.isPaywallOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            PaywallView()
                .presentationDragIndicator(.visible)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
        }
        .sheet(isPresented: $viewModel.isUserProfileOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            UserProfileView()
                .presentationDragIndicator(.visible)
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
                .presentationDragIndicator(.visible)
                .onAppear {
                    viewModel.handleSheetAppear()
                }
        }
        .sheet(isPresented: $viewModel.isLifeListOpen, onDismiss: {
            viewModel.handleSheetDismiss()
        }) {
            LifeListSearchView(isInsightSheetOpen: $viewModel.isInsightSheetOpen)
                .presentationDragIndicator(.visible)
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
