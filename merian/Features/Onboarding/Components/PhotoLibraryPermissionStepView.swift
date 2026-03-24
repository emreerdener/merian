import SwiftUI
import Photos

struct PhotoLibraryPermissionStepView: View {
    // MARK: - Callbacks
    let onNext: () -> Void
    
    // MARK: - Visual Layout
    var body: some View {
        OnboardingStepWrapper(
            iconColor: Color.purple.opacity(0.1),
            iconText: "Photos Rive Animation",
            iconCornerRadius: 64,
            title: "Archive your\ndiscoveries",
            subtitle: "Merian needs access to your Photo Library to save your high-resolution taxonomy images seamlessly.",
            primaryButtonTitle: "Enable photo access",
            primaryButtonTextColor: Color.white,
            primaryButtonColor: Color.purple.opacity(0.8),
            primaryAction: {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .notDetermined {
                    PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                        Task { @MainActor in onNext() }
                    }
                } else {
                    // Safe fallback if permissions were historically logged natively before flow reset
                    onNext()
                }
            },
            secondaryButtonTitle: "Skip for now",
            secondaryAction: onNext
        )
    }
}
