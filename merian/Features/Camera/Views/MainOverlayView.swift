import SwiftUI
import PhotosUI

struct MainOverlayView: View {
    // MARK: - Dependencies
    let latestThumbnail: UIImage?
    let isFlashEnabled: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var activeSheet: CameraViewModel.ActiveSheet?
    let activeScanImages: [UIImage]
    let onCapture: () -> Void
    let onToggleFlash: () -> Void
    let onThumbnailTap: (Int) -> Void
    let onSubmitScan: () -> Void
    let onCancelScan: () -> Void
    
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
            if activeScanImages.count < 2 {
                MediaModeToggle(activeMode: $activeMode)
                    .padding(.top, 16) // Natively clears the safe area boundaries
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
            
            // MARK: - Dynamic Intelligence
            if activeScanImages.count < 2 {
                ViewfinderHints()
                    .transition(.opacity)
            }
            
            // MARK: - Hardware Capture Bar
            if activeScanImages.count < 2 {
                HStack(alignment: .bottom) {
                    PhotoLibraryButton(
                        selectedPhotoItems: $selectedPhotoItems,
                        latestThumbnail: latestThumbnail,
                        maxSelectionCount: max(1, 2 - activeScanImages.count)
                    )
                    
                    Spacer()
                    
                    ShutterButton(onCapture: onCapture)
                    
                    Spacer()
                    
                    FlashButton(isFlashEnabled: isFlashEnabled, onToggleFlash: onToggleFlash)
                }
                .padding(.bottom, activeScanImages.isEmpty ? 24 : 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // MARK: - Global App Navigation & Active Scan Panel
            // Maps MainTabBar tabs directly to their overarching CameraSheetRouter payloads 
            if activeScanImages.isEmpty {
                MainTabBar(
                    isScansOpen: isScansOpen,
                    isUserProfileOpen: isUserProfileOpen
                )
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ActiveScanToolbar(
                    images: activeScanImages,
                    selectedPhotoItems: $selectedPhotoItems,
                    onThumbnailTap: onThumbnailTap,
                    onCancel: onCancelScan,
                    onSubmit: onSubmitScan
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeScanImages.count)
    }
}
