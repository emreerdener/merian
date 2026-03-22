import SwiftUI
import PhotosUI

struct MainOverlayView: View {
    // MARK: - Dependencies
    let latestThumbnail: UIImage?
    let isFlashEnabled: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var activeSheet: CameraViewModel.ActiveSheet?
    let onCapture: () -> Void
    let onToggleFlash: () -> Void
    
    // MARK: - Local Staging State
    @State private var activeMode: CaptureMode = .visual
    
    // MARK: - Navigation Encoders
    // Computes bidirectional view states natively mapped directly into CameraSheetRouter
    private var isScansOpen: Binding<Bool> {
        Binding(
            get: { activeSheet == .scans }, 
            set: { if $0 { activeSheet = .scans } else if activeSheet == .scans { activeSheet = nil } }
        )
    }
    
    private var isUserProfileOpen: Binding<Bool> {
        Binding(
            get: { activeSheet == .profile }, 
            set: { if $0 { activeSheet = .profile } else if activeSheet == .profile { activeSheet = nil } }
        )
    }
    
    // MARK: - Interface Layout
    var body: some View {
        VStack {
            // MARK: - Media Mode Scoping (Staging)
            MediaModeToggle(activeMode: $activeMode)
                .padding(.top, 16) // Natively clears the safe area boundaries
            
            Spacer()
            
            // MARK: - Dynamic Intelligence
            ViewfinderHints()
            
            // MARK: - Hardware Capture Bar
            HStack(alignment: .bottom) {
                PhotoLibraryButton(selectedPhotoItem: $selectedPhotoItem, latestThumbnail: latestThumbnail)
                
                Spacer()
                
                ShutterButton(onCapture: onCapture)
                
                Spacer()
                
                FlashButton(isFlashEnabled: isFlashEnabled, onToggleFlash: onToggleFlash)
            }
            .padding(.bottom, 24)
            
            // MARK: - Global App Navigation
            // Maps MainTabBar tabs directly to their overarching CameraSheetRouter payloads 
            MainTabBar(
                isScansOpen: isScansOpen,
                isUserProfileOpen: isUserProfileOpen
            )
            .padding(.bottom, 24)
        }
    }
}
