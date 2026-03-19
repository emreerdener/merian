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
            
            
            if showFocusIndicator, let location = focusLocation {
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
                .allowsHitTesting(false)
            
            // Thermal Warning Indicator overlay
            ThermalWarningOverlay()
            
            // Action Overlay Context
            if !viewModel.isAnalyzingFullscreen {
                // Extracted Shutter Button Overlay
                VStack {

                    
                    Spacer()
                    
                    // Viewfinder Intelligence Hint Banner
                    ViewfinderHintBanner()
                    
                    HStack(alignment: .bottom) {
                        // Photo Library Button
                        let thumb = photoLibraryManager.latestThumbnail
                        PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            ZStack {
                                if let thumbnail = thumb {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 32)
                        
                        Spacer()
                        
                        // Shutter Button
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 1)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 72, height: 72)
                        }
                        .environment(\.colorScheme, .dark)
                        .onTapGesture {
                            viewModel.executeCapture()
                        }
                        .padding(.bottom, 32) // Elevates shutter specifically
                        
                        Spacer()
                        
                        // Flash toggle
                        Button(action: {
                            cameraManager.toggleFlash()
                        }) {
                            Image(systemName: cameraManager.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(cameraManager.isFlashEnabled ? .yellow : .white)
                                .frame(width: 50, height: 50)
                                .background(.ultraThinMaterial, in: Circle())
                                .environment(\.colorScheme, .dark)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 32)
                    }
                    .padding(.bottom, 24)
                    
                    MainTabBar(
                        isScansOpen: Binding(
                            get: { viewModel.activeSheet == .scans }, 
                            set: { if $0 { viewModel.activeSheet = .scans } else if viewModel.activeSheet == .scans { viewModel.activeSheet = nil } }
                        ),
                        isUserProfileOpen: Binding(
                            get: { viewModel.activeSheet == .profile }, 
                            set: { if $0 { viewModel.activeSheet = .profile } else if viewModel.activeSheet == .profile { viewModel.activeSheet = nil } }
                        ),
                        isSettingsOpen: Binding(
                            get: { viewModel.activeSheet == .settings }, 
                            set: { if $0 { viewModel.activeSheet = .settings } else if viewModel.activeSheet == .settings { viewModel.activeSheet = nil } }
                        )
                    )
                    .padding(.bottom, 24)
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
        // Unified Application Sheet Router Overlay
        .sheet(item: $viewModel.activeSheet, onDismiss: {
            viewModel.handleSheetDismiss()
        }) { sheet in
            Group {
                switch sheet {
                case .insight:
                    InsightSheetView(isPresented: Binding(
                        get: { viewModel.activeSheet == .insight },
                        set: { if !$0 && viewModel.activeSheet == .insight { viewModel.activeSheet = nil } }
                    ))
                case .paywall:
                    PaywallView()
                case .profile:
                    UserProfileView()
                case .scans:
                    ScansSearchView(isInsightSheetOpen: Binding(
                        get: { viewModel.activeSheet == .insight },
                        set: { if $0 { viewModel.activeSheet = .insight } else if viewModel.activeSheet == .insight { viewModel.activeSheet = nil } }
                    ))
                case .settings:
                    SettingsView()
                }
            }
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



