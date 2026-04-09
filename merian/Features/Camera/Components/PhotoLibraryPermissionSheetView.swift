import Photos
import SwiftUI

struct PhotoLibraryPermissionSheetView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.purple)
                .padding(.top, 32)
            
            VStack(spacing: 8) {
                Text("Archive your discoveries")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Merian needs access to your Photo Library to seamlessly save your high-resolution taxonomy images and metadata to your camera roll.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                Button {
                    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                    if status == .notDetermined {
                        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                            Task { @MainActor in onDismiss() }
                        }
                    } else if status == .denied || status == .restricted {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                        onDismiss()
                    } else {
                        onDismiss()
                    }
                } label: {
                    Text("Enable photo access")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .clipShape(Capsule())
                }
                
                Button {
                    onDismiss()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}
