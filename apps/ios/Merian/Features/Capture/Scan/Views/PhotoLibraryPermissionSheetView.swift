import Photos
import SwiftUI

struct PhotoLibraryPermissionSheetView: View {
    enum PermissionKind {
        case importPhotos
        case saveToCameraRoll

        var accessLevel: PHAccessLevel {
            switch self {
            case .importPhotos:
                return .readWrite
            case .saveToCameraRoll:
                return .addOnly
            }
        }

        var icon: String {
            switch self {
            case .importPhotos:
                return "photo.on.rectangle"
            case .saveToCameraRoll:
                return "square.and.arrow.down"
            }
        }

        var tint: Color {
            switch self {
            case .importPhotos:
                return .purple
            case .saveToCameraRoll:
                return .teal
            }
        }

        var title: String {
            switch self {
            case .importPhotos:
                return "Photo library access"
            case .saveToCameraRoll:
                return "Save captures to Photos"
            }
        }

        var message: String {
            switch self {
            case .importPhotos:
                return "Naturebook needs access to your Photo Library to upload your images to be analyzed."
            case .saveToCameraRoll:
                return "Naturebook can save new scan photos to your library without seeing your existing photos."
            }
        }

        var actionTitle: String {
            switch self {
            case .importPhotos:
                return "Enable photo access"
            case .saveToCameraRoll:
                return "Allow saving"
            }
        }
    }

    var kind: PermissionKind = .importPhotos
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: kind.icon)
                .font(.system(size: 48))
                .foregroundColor(kind.tint)
                .padding(.top, 32)
            
            VStack(spacing: 8) {
                Text(kind.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(kind.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 16) {
                Button {
                    let status = PHPhotoLibrary.authorizationStatus(for: kind.accessLevel)
                    if status == .notDetermined {
                        PHPhotoLibrary.requestAuthorization(for: kind.accessLevel) { _ in
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
                    Text(kind.actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(kind.tint)
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
