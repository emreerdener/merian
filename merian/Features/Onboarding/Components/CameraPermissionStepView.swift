import SwiftUI
import AVFoundation
import RiveRuntime

struct CameraPermissionStepView: View {
    let onNext: () -> Void
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // TODO: Drop RiveViewModel file here
            Rectangle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 250, height: 250)
                .clipShape(Circle())
                .overlay(Text("Camera Rive Animation").foregroundColor(.gray))
            
            VStack(spacing: 16) {
                Text("We need to see\nwhat you see")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Enable camera access so Merian can identify the natural world right in front of you. We never record without your permission.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            
            Button {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        // We advance automatically immediately upon boundary completion cleanly
                        onNext()
                    }
                }
            } label: {
                Text("Enable Camera")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 64)
        }
    }
}
