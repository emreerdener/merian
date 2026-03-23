import SwiftUI
import AVFoundation
import AVKit

// MARK: - Hardware Video Bridge
// SwiftUI bridging of AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    // MARK: - Dependencies
    var session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void
    
    // MARK: - UIKit Substrate Layer
    // The literal backing geometry that receives AVFoundation visual frames.
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    // MARK: - SwiftUI Lifecycle Bridging
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        return view
    }
    
    // MARK: - View Update Lifecycle
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        context.coordinator.parent = self
    }
    
    // MARK: - View Deallocation
    // Ensures AVFoundation layers don't leak by retaining global session traces past the View boundary.
    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        uiView.videoPreviewLayer.session = nil
    }
    
    // MARK: - Gesture Coordinator & Delegates
    // Translates legacy imperative UITapGestureRecognizer events cleanly back out to SwiftUI closures.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view as? PreviewView else { return }
            let layerPoint = sender.location(in: view)
            let devicePoint = view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            parent.onTap(layerPoint, devicePoint)
        }
    }
}
