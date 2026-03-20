import SwiftUI
import PhotosUI

struct CameraControlsOverlayView: View {
    let latestThumbnail: UIImage?
    let isFlashEnabled: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var activeSheet: CameraViewModel.ActiveSheet?
    let onCapture: () -> Void
    let onToggleFlash: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            // Viewfinder Intelligence Hint Banner
            ViewfinderHintBanner()
            
            HStack(alignment: .bottom) {
                // Photo Library Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        if let thumbnail = latestThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
                .padding(.leading, 32)
                
                Spacer()
                
                // Shutter Button
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                }
                .environment(\.colorScheme, .dark)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onCapture()
                }
                .padding(.bottom, 32)
                
                Spacer()
                
                // Flash toggle
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onToggleFlash()
                }) {
                    Image(systemName: isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isFlashEnabled ? .yellow : .white)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 32)
            }
            .padding(.bottom, 24)
            
            MainTabBar(
                isScansOpen: Binding(
                    get: { activeSheet == .scans }, 
                    set: { if $0 { activeSheet = .scans } else if activeSheet == .scans { activeSheet = nil } }
                ),
                isUserProfileOpen: Binding(
                    get: { activeSheet == .profile }, 
                    set: { if $0 { activeSheet = .profile } else if activeSheet == .profile { activeSheet = nil } }
                )
            )
            .padding(.bottom, 24)
        }
    }
}
