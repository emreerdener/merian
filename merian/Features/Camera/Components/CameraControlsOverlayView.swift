import SwiftUI
import PhotosUI

struct CameraControlsOverlayView: View {
    @ObservedObject var viewModel: CameraViewModel
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var photoLibraryManager: PhotoLibraryManager
    
    var body: some View {
        VStack {
            Spacer()
            
            // Viewfinder Intelligence Hint Banner
            ViewfinderHintBanner()
            
            HStack(alignment: .bottom) {
                // Photo Library Button
                let thumb = photoLibraryManager.latestThumbnail
                PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        if let thumbnail = thumb {
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
                    viewModel.executeCapture()
                }
                .padding(.bottom, 32)
                
                Spacer()
                
                // Flash toggle
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    cameraManager.toggleFlash()
                }) {
                    Image(systemName: cameraManager.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(cameraManager.isFlashEnabled ? .yellow : .white)
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
                    get: { viewModel.activeSheet == .scans }, 
                    set: { if $0 { viewModel.activeSheet = .scans } else if viewModel.activeSheet == .scans { viewModel.activeSheet = nil } }
                ),
                isUserProfileOpen: Binding(
                    get: { viewModel.activeSheet == .profile }, 
                    set: { if $0 { viewModel.activeSheet = .profile } else if viewModel.activeSheet == .profile { viewModel.activeSheet = nil } }
                )
            )
            .padding(.bottom, 24)
        }
    }
}
