import SwiftUI
import Photos
import RiveRuntime

struct PhotoLibraryPermissionStepView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // TODO: Drop RiveViewModel file here
            Rectangle()
                .fill(Color.purple.opacity(0.1))
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 64, style: .continuous))
                .overlay(Text("Photos Rive Animation").foregroundColor(.gray))
            
            VStack(spacing: 16) {
                Text("Archive your\ndiscoveries")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Merian needs access to your Photo Library to save your high-resolution taxonomy images seamlessly.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status == .notDetermined {
                        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                            DispatchQueue.main.async {
                                onNext() // Auto advance after selection
                            }
                        }
                    } else {
                        // Safe fallback if permissions were historically logged natively before flow reset
                        onNext()
                    }
                } label: {
                    Text("Enable photo access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple.opacity(0.8))
                        .clipShape(Capsule())
                }
                
                Button(action: onNext) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
