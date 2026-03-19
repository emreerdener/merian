import SwiftUI
import AVFoundation

struct CameraPermissionStepView: View {
    let onNext: () -> Void
    var body: some View {
        BaseOnboardingStepView(
            iconColor: Color.blue.opacity(0.1),
            iconText: "Camera Rive Animation",
            iconCornerRadius: 125, // 250/2 evaluates perfectly to a Circle
            title: "We need to see\nwhat you see",
            subtitle: "Enable camera access so Merian can identify the natural world right in front of you. We never record without your permission.",
            primaryButtonTitle: "Enable camera",
            primaryButtonTextColor: Color.white,
            primaryButtonColor: Color.blue,
            primaryAction: {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        // We advance automatically immediately upon boundary completion cleanly
                        onNext()
                    }
                }
            }
        )
    }
}
