import SwiftUI
import AVFoundation

struct CameraRootView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var hardwareOrchestrator = HardwareOrchestrator.shared
    
    @State private var isInsightSheetOpen: Bool = false
    
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
                
                // Floating Action Bar Interface
                HStack {
                    Spacer()
                    
                    // The Shutter / Analyze Button
                    Button(action: {
                        isInsightSheetOpen = true
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
                    
                    Spacer()
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
            InsightSheetView(speciesData: nil, isPresented: $isInsightSheetOpen)
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


