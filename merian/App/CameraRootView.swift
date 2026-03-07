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
    
    var body: some View {
        ZStack {
            // Full-bleed camera feed
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
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
                HStack {
                    // Left Vertical Overlay (Life List & Gamification)
                    VStack(spacing: 16) {
                        Button(action: {
                            isLifeListOpen = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "books.vertical.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Button(action: {
                            gamificationManager.showTerrariumSheet = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 50, height: 50)
                                Image(systemName: "leaf.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.leading, 12)
                    
                    Spacer()
                    
                    // The Shutter / Analyze Button
                    Button(action: {
                        if usageManager.canPerformScan(isProActive: revenueCatManager.isProActive) {
                            Task {
                                do {
                                    let captureData = try await cameraManager.captureImage()
                                    OfflineQueueManager.shared.enqueueCapture(imageData: captureData)
                                    
                                    await MainActor.run {
                                        inferenceEngine.analyze(imageData: captureData, modelContext: modelContext)
                                        usageManager.recordSuccessfulScan()
                                        gamificationManager.recordNewSpeciesDiscovered()
                                        AppTelemetry.trackScan(isPro: revenueCatManager.isProActive)
                                        isInsightSheetOpen = true
                                    }
                                } catch {
                                    print("⚠️ Shutter failure: \(error.localizedDescription)")
                                }
                            }
                        } else {
                            // User hit the strict architectural boundary of 3 free logs
                            AppTelemetry.trackPaywallImpression()
                            isPaywallOpen = true
                        }
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 72, height: 72)
                            
                            Circle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 62, height: 62)
                        }
                    }
                    
                    // Photo Library Picker Right Overlay
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 50, height: 50)
                            Image(systemName: "photo.on.rectangle")
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 12)
                }
                .padding(.vertical, 16)
                // State-based Glassmorphism
                .background(
                    Group {
                        if hardwareOrchestrator.isGlassmorphismEnabled {
                            VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)
                        } else {
                            Color.black.opacity(0.85)
                        }
                    }
                )
                .clipShape(Capsule())
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
        // Insight Data View overlay 
        .sheet(isPresented: $isInsightSheetOpen, onDismiss: {
            // Restore appropriate target FPS from idle state based on hardware orchestrator targets
            cameraManager.restoreFromIdleState()
        }) {
            InsightSheetView(isPresented: $isInsightSheetOpen)
                .onAppear {
                    // Start cooling down AV session
                    cameraManager.throttleToIdleState()
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
        .sheet(isPresented: $isPaywallOpen) {
            PaywallView()
        }
        .sheet(isPresented: $gamificationManager.showTerrariumSheet) {
            TerrariumView()
        }
        .sheet(isPresented: $isLifeListOpen) {
            LifeListSearchView()
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


