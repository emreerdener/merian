import SwiftUI
import PhotosUI

struct MainOverlayView: View {
    // MARK: - Dependencies
    let latestThumbnail: UIImage?
    let isFlashEnabled: Bool
    let isTooltipVisible: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var activeSheet: CameraViewModel.ActiveSheet?
    let activeScanImages: [UIImage]
    let onCapture: () -> Void
    let onToggleFlash: () -> Void
    let onThumbnailTap: (Int) -> Void
    let onSubmitScan: () -> Void
    let onCancelScan: () -> Void
    let onModeChange: () -> Void
    
    // MARK: - Local Staging State
    @State private var activeMode: CaptureMode = .visual
    @AppStorage("multiImageScanMode") private var multiImageScanMode: Bool = false
    
    // MARK: - Interface Layout
    var body: some View {
        VStack {
            // MARK: - Media Mode Scoping (Staging)
            if activeScanImages.count < 2 {
                MediaModeToggle(
                    activeMode: $activeMode,
                    isTooltipVisible: isTooltipVisible,
                    onModeChange: onModeChange
                )
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
                HStack(alignment: .center) {
                    PhotoLibraryButton(
                        selectedPhotoItems: $selectedPhotoItems,
                        latestThumbnail: latestThumbnail,
                        maxSelectionCount: multiImageScanMode ? max(1, 2 - activeScanImages.count) : 1
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
                    isScansOpen: $activeSheet.mapped(to: .scans),
                    isUserProfileOpen: $activeSheet.mapped(to: .profile)
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
        .overlay(alignment: .trailing) {
            if activeScanImages.isEmpty {
                ZoomSliderView()
                    .padding(.trailing, 16)
                    .padding(.bottom, 110)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeScanImages.count)
    }
}

// MARK: - Binding Encoders
extension Binding where Value == CameraViewModel.ActiveSheet? {
    /// Ergonomically maps an optional active sheet enumeration directly into boolean bindings for standard SwiftUI UI elements
    func mapped(to target: CameraViewModel.ActiveSheet) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue == target },
            set: { newValue in
                if newValue {
                    self.wrappedValue = target
                } else if self.wrappedValue == target {
                    self.wrappedValue = nil
                }
            }
        )
    }
}
