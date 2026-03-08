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
    @State private var shutterRadius: CGFloat = 2000
    
    var body: some View {
        ZStack {
            // Full-bleed camera feed
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            // Camera Shutter Aperture Overlay
            Color.black
                .ignoresSafeArea()
                .clipShape(ApertureMask(holeRadius: shutterRadius), style: FillStyle(eoFill: true))

            
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
                    selectedPhotoItem: $selectedPhotoItem
                )
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
                        isInsightSheetOpen = true
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
    }
    
    private func handleSheetAppear() {
        // Animate the aperture closing over the camera feed
        withAnimation(.easeInOut(duration: 0.5)) {
            shutterRadius = 0
        }
        
        // Once closed, fully power down the camera AV session behind the sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            cameraManager.stopSession()
        }
    }
    
    private func handleSheetDismiss() {
        // Instead of returning to idle, we fully power back on the camera and animate the shutter
        Task {
            cameraManager.startSession()
            
            // Allow a few seconds for the hardware to wake up and start streaming frames
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            
            await MainActor.run {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                    shutterRadius = 2000
                }
            }
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

// Custom shape for the closing/opening camera aperture mask
struct ApertureMask: Shape {
    var holeRadius: CGFloat
    
    var animatableData: CGFloat {
        get { holeRadius }
        set { holeRadius = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        // Ensure the hole fits cleanly minus out the center of the mask bounds
        let holeRect = CGRect(
            x: rect.midX - holeRadius,
            y: rect.midY - holeRadius,
            width: holeRadius * 2,
            height: holeRadius * 2
        )
        // By drawing the outermost rect and then drawing an ellipse in it, 
        // passing eoFill: true to clipShape will subtract the ellipse.
        path.addPath(Path(ellipseIn: holeRect))
        return path
    }
}
