import SwiftUI
import AVFoundation
import AVKit

// MARK: - Hardware Video Bridge
// SwiftUI bridging of AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    // MARK: - Dependencies
    var session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void
    /// Called when the user swipes right-to-left across the viewfinder.
    /// Reserved for the future audio recording mode transition — pass `nil` until that view exists.
    var onSwipeLeft: (() -> Void)? = nil
    
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

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(pinchGesture)

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

        // MARK: - Gesture state
        private var panStartZoom: CGFloat = 1.0
        private var panDirection: PanDirection = .undetermined
        private var pinchStartZoom: CGFloat = 1.0

        private enum PanDirection { case undetermined, vertical, horizontal }

        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view as? PreviewView else { return }
            let layerPoint = sender.location(in: view)
            let devicePoint = view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            parent.onTap(layerPoint, devicePoint)
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            // UIKit calls gesture handlers on the main thread — assumeIsolated is safe here.
            let state = sender.state
            let scale = sender.scale
            MainActor.assumeIsolated {
                switch state {
                case .began:
                    pinchStartZoom = CameraManager.shared.zoomFactor
                case .changed:
                    let proposed = min(max(pinchStartZoom * scale, 1.0), CameraManager.shared.maxZoomFactor)
                    CameraManager.shared.setZoom(factor: proposed)
                default:
                    break
                }
            }
        }

        /// Vertical pan → zoom in/out. Horizontal pan ending left → reserved for audio mode (future).
        /// Direction is locked on the first frame where velocity is unambiguous, preventing diagonal drift.
        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let view = sender.view else { return }
            // Capture non-isolated sender values before crossing the actor boundary.
            let state      = sender.state
            let velocity   = sender.velocity(in: view)
            let translation = sender.translation(in: view)

            // UIKit calls gesture handlers on the main thread — assumeIsolated is safe here.
            MainActor.assumeIsolated {
                switch state {
                case .began:
                    panDirection = .undetermined
                    panStartZoom = CameraManager.shared.zoomFactor

                case .changed:
                    if panDirection == .undetermined {
                        if abs(velocity.y) > abs(velocity.x) {
                            panDirection = .vertical
                        } else if abs(velocity.x) > abs(velocity.y) {
                            panDirection = .horizontal
                        }
                    }
                    guard panDirection == .vertical else { return }
                    let range = max(1.0, CameraManager.shared.maxZoomFactor - 1.0)
                    // Default: swipe up (negative Y) = zoom in. Inverted: swipe down (positive Y) = zoom in.
                    let sign: CGFloat = UserDefaults.standard.bool(forKey: UserDefaultsKeys.invertZoomDirection) ? 1.0 : -1.0
                    let delta = (sign * translation.y / 500) * range
                    let proposed = min(max(panStartZoom + delta, 1.0), CameraManager.shared.maxZoomFactor)
                    CameraManager.shared.setZoom(factor: proposed)

                case .ended, .cancelled:
                    if panDirection == .horizontal && velocity.x < -200 {
                        parent.onSwipeLeft?()
                    }
                    panDirection = .undetermined

                default:
                    break
                }
            }
        }
    }
}
