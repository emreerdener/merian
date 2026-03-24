import SwiftUI
import AVFoundation

struct CameraPermissionStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            iconColor: Color.blue.opacity(0.1),
            iconText: "Camera Rive Animation",
            iconCornerRadius: 125, // 250/2 evaluates perfectly to a Circle
            title: "We need to see\nwhat you see",
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
