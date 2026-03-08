import SwiftUI
import AVFoundation
import PhotosUI
import SwiftData

struct CameraRootView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var hardwareOrchestrator = HardwareOrchestrator.shared
    @StateObject private var vui = ViewfinderIntelligence.shared
    
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @EnvironmentObject var usageManager: UsageManager
    @EnvironmentObject var gamificationManager: GamificationManager
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var isInsightSheetOpen: Bool = false
    @State private var isPaywallOpen: Bool = false
    @State private var isLifeListOpen: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var flashOpacity: Double = 0.0
    
    @State private var isAnalyzingFullscreen: Bool = false
    @State private var scanningPhaseText: String = "Scanning..."
    @State private var isPulseAnimating: Bool = false
    
    var body: some View {
        ZStack {
            // Full-bleed camera feed
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            // Shutter Snap Animation
            Color.black
                .ignoresSafeArea()
                .opacity(flashOpacity)
            
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
            if !isAnalyzingFullscreen {
                VStack {
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
                        isLifeListOpen: $isLifeListOpen,
                        isPaywallOpen: $isPaywallOpen,
                        isInsightSheetOpen: $isInsightSheetOpen,
                        isAnalyzingFullscreen: $isAnalyzingFullscreen,
                        selectedPhotoItem: $selectedPhotoItem,
                        onCaptureTriggered: triggerFlash
                    )
                }
            }
            
            // Full-Screen Scanning Overlay
            if isAnalyzingFullscreen, let payload = inferenceEngine.activePayload, let uiImage = UIImage(data: payload) {
                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                    
                    ZStack {
                        // Base darkening layer
                        Color.black.opacity(isPulseAnimating ? 0.1 : 0.4)
                            .ignoresSafeArea()
                        
                        // Perfectly aligned 4-edge rainbow gradient
                        ZStack {
                            // Left edge
                            LinearGradient(colors: [.cyan, .teal, .green], startPoint: .top, endPoint: .bottom)
                                .frame(width: isPulseAnimating ? 40 : 20)
                                .blur(radius: isPulseAnimating ? 20 : 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Right edge
                            LinearGradient(colors: [.pink, .red, .orange], startPoint: .top, endPoint: .bottom)
                                .frame(width: isPulseAnimating ? 40 : 20)
                                .blur(radius: isPulseAnimating ? 20 : 10)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            
                            // Top edge
                            LinearGradient(colors: [.cyan, .blue, .purple, .pink], startPoint: .leading, endPoint: .trailing)
                                .frame(height: isPulseAnimating ? 40 : 20)
                                .blur(radius: isPulseAnimating ? 20 : 10)
                                .frame(maxHeight: .infinity, alignment: .top)
                            
                            // Bottom edge
                            LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                .frame(height: isPulseAnimating ? 40 : 20)
                                .blur(radius: isPulseAnimating ? 20 : 10)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .hueRotation(.degrees(isPulseAnimating ? 360 : 0))
                        .opacity(isPulseAnimating ? 0.9 : 0.6)
                        .ignoresSafeArea()
                    }
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isPulseAnimating)
                    .onAppear {
                        isPulseAnimating = true
                    }
                    .onDisappear {
                        isPulseAnimating = false
                    }
                    
                    VStack {
                        Spacer()
                        Text(scanningPhaseText)
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
        .sheet(isPresented: $isInsightSheetOpen, onDismiss: {
            handleSheetDismiss()
        }) {
            InsightSheetView(isPresented: $isInsightSheetOpen)
                .presentationDragIndicator(.visible)
                .onAppear {
                    handleSheetAppear()
                }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                guard let newItem = newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                
                if usageManager.canPerformScan(isProActive: revenueCatManager.isProActive) {
                    await MainActor.run {
                        inferenceEngine.analyze(imageData: data, modelContext: modelContext)
                        usageManager.recordSuccessfulScan()
                        gamificationManager.recordNewSpeciesDiscovered()
                        AppTelemetry.trackScan(isPro: revenueCatManager.isProActive)
                        isAnalyzingFullscreen = true
                        selectedPhotoItem = nil
                    }
                } else {
                    await MainActor.run {
                        AppTelemetry.trackPaywallImpression()
                        isPaywallOpen = true
                    }
                }
            }
        }
        .sheet(isPresented: $isPaywallOpen, onDismiss: {
            handleSheetDismiss()
        }) {
            PaywallView()
                .presentationDragIndicator(.visible)
                .onAppear {
                    handleSheetAppear()
                }
        }
        .sheet(isPresented: $gamificationManager.showTerrariumSheet, onDismiss: {
            handleSheetDismiss()
        }) {
            TerrariumView()
                .presentationDragIndicator(.visible)
                .onAppear {
                    handleSheetAppear()
                }
        }
        .sheet(isPresented: $isLifeListOpen, onDismiss: {
            handleSheetDismiss()
        }) {
            LifeListSearchView(isInsightSheetOpen: $isInsightSheetOpen)
                .presentationDragIndicator(.visible)
                .onAppear {
                    handleSheetAppear()
                }
        }
        .onChange(of: isAnalyzingFullscreen) { _, isFullscreen in
            if isFullscreen {
                cameraManager.stopSession() // Revert viewport to off while analyzing over it
                scanningPhaseText = "Scanning..."
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if isAnalyzingFullscreen {
                        withAnimation {
                            scanningPhaseText = "Identifying..."
                        }
                    }
                }
            } else {
                if !isInsightSheetOpen {
                    cameraManager.startSession()
                }
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            if !isStillProcessing && isAnalyzingFullscreen {
                withAnimation {
                    isAnalyzingFullscreen = false
                }
                isInsightSheetOpen = true
            }
        }
    }
    
    private func handleSheetAppear() {
        cameraManager.stopSession()
    }
    
    private func handleSheetDismiss() {
        cameraManager.startSession()
    }
    
    private func triggerFlash() {
        flashOpacity = 1.0
        withAnimation(.easeOut(duration: 0.15)) {
            flashOpacity = 0.0
        }
    }
}

// SwiftUI bridging of AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// UIVisualEffectView SwiftUI Wrapper
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}


