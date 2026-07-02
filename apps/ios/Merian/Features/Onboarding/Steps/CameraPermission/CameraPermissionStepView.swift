import AVFoundation
import SwiftUI

struct CameraPermissionStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            imageName: "camera",
            title: "Lens for\ndiscovery",
            subtitle: "Enable camera access so Merian can identify the natural world right in front of you. We never record without your permission.",
            primaryButtonTitle: "Enable camera",
            primaryButtonTextColor: Color.white,
            primaryButtonColor: Color.blue,
            primaryAction: {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in onNext() }
                }
            }
        )
    }
}
