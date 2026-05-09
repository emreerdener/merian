import AVKit
import SwiftUI

private enum CameraPanDirection { case undetermined, vertical, horizontal }

// MARK: - Hardware Video Bridge
// SwiftUI bridging of AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    @Environment(AppSettings.self) private var appSettings

    // MARK: - Dependencies
    var session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void
    /// Called when the user swipes right-to-left across the viewfinder.
    /// Reserved for the future audio recording mode transition — pass `nil` until that view exists.
    var onSwipeLeft: (() -> Void)?
    /// Called with `true` when a vertical (zoom) drag locks in, `false` when it ends.
    /// Use this to disable the outer paging ScrollView during active zoom drags.
    var onVerticalDragActiveChanged: ((Bool) -> Void)?
    
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
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(pinchGesture)

        context.coordinator.startObservingZoom(in: view)

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
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraPreviewView

        // MARK: - Gesture state
        private var panStartZoom: CGFloat = 1.0
        private var panDirection: CameraPanDirection = .undetermined
        private var pinchStartZoom: CGFloat = 1.0

        // MARK: - Lens-switch crossfade state
        private var lastZoomFactor: CGFloat = 1.0
        private weak var lensTransitionOverlay: UIView?
        private var lensTransitionTask: Task<Void, Never>?

        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }

        // MARK: - UIGestureRecognizerDelegate

        /// Allows the camera pan recognizer to fire alongside the outer UIScrollView's
        /// pan recognizer. Without this, the inner pan wins the gesture competition and
        /// blocks the paging scroll view from recognizing horizontal swipes.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        // MARK: - Lens-switch crossfade

        /// Starts a recursive withObservationTracking chain watching zoomFactor.
        /// When the factor crosses an optical stop the coordinator snapshots the current
        /// preview frame and fades it out, hiding the physical lens-switch discontinuity.
        /// The chain self-terminates when the coordinator is deallocated ([weak self]).
        @MainActor func startObservingZoom(in view: PreviewView) {
            withObservationTracking {
                _ = CameraManager.shared.zoomFactor
            } onChange: { [weak self, weak view] in
                guard let self, let view else { return }
                // onChange fires synchronously during the property write — jump to the
                // next main-actor iteration so zoomFactor has its committed value and
                // the snapshot is taken before the background ramp reaches the hardware.
                Task { @MainActor [weak self, weak view] in
                    guard let self, let view else { return }
                    let newFactor = CameraManager.shared.zoomFactor
                    self.handleLensSwitchIfNeeded(newFactor: newFactor, in: view)
                    self.startObservingZoom(in: view)
                }
            }
        }

        @MainActor private func handleLensSwitchIfNeeded(newFactor: CGFloat, in view: PreviewView) {
            defer { lastZoomFactor = newFactor }

            // Skip during session setup / zoom reset so we don't flash on startup.
            guard CameraManager.shared.isSessionRunning else { return }

            let stops = CameraManager.shared.opticalZoomStops.filter { $0 > 1.0 }
            guard stops.contains(where: { stop in
                (lastZoomFactor < stop) != (newFactor < stop)
            }) else { return }

            // Cancel any in-flight crossfade before starting a new one.
            lensTransitionTask?.cancel()
            lensTransitionOverlay?.removeFromSuperview()

            // Snapshot the current composited frame. This runs before the background
            // camera queue processes the ramp command, so it always captures the
            // pre-switch image.
            guard let overlay = view.snapshotView(afterScreenUpdates: false) else { return }
            overlay.frame = view.bounds
            view.addSubview(overlay)
            lensTransitionOverlay = overlay

            // Hold long enough for the hardware to switch and stabilise, then fade out.
            lensTransitionTask = Task { @MainActor [weak self, weak overlay] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let overlay else { return }
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
                    overlay.alpha = 0
                } completion: { [weak self, weak overlay] _ in
                    overlay?.removeFromSuperview()
                    if let overlay, self?.lensTransitionOverlay === overlay {
                        self?.lensTransitionOverlay = nil
                    }
                }
            }
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
                case .ended, .cancelled:
                    CameraManager.shared.snapToNearestOpticalStop()
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
                            parent.onVerticalDragActiveChanged?(true)
                        } else if abs(velocity.x) > abs(velocity.y) {
                            panDirection = .horizontal
                        }
                    }
                    guard panDirection == .vertical else { return }
                    let range = max(1.0, CameraManager.shared.maxZoomFactor - 1.0)
                    // Default: swipe up (negative Y) = zoom in. Inverted: swipe down (positive Y) = zoom in.
                    let sign: CGFloat = parent.appSettings.invertZoomDirection ? 1.0 : -1.0
                    let delta = (sign * translation.y / 600) * range
                    let proposed = min(max(panStartZoom + delta, 1.0), CameraManager.shared.maxZoomFactor)
                    CameraManager.shared.setZoom(factor: proposed)

                case .ended, .cancelled:
                    if panDirection == .horizontal && velocity.x < -200 {
                        parent.onSwipeLeft?()
                    }
                    if panDirection == .vertical {
                        parent.onVerticalDragActiveChanged?(false)
                    }
                    panDirection = .undetermined
                    CameraManager.shared.snapToNearestOpticalStop()

                default:
                    break
                }
            }
        }
    }
}
