import SwiftUI
import PhotosUI

struct ThermalWarningOverlay: View {
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    var body: some View {
        if hardwareOrchestrator.isCriticalHeatWarningActive {
            VStack {
                Text("DEVICE CRITICAL HEAT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                Spacer()
            }
            .padding(.top, 40)
        }
    }
}

struct ViewfinderHintBanner: View {
    @EnvironmentObject var vui: ViewfinderIntelligence
    
    var body: some View {
        if !vui.isOptimal {
            Text(vui.currentHint.rawValue)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(Capsule())
                .padding(.bottom, 16)
        }
    }
}

@MainActor
struct TopToolbarView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    @EnvironmentObject var photoLibraryManager: PhotoLibraryManager
    
    @Binding var selectedPhotoItem: PhotosPickerItem?
    
    var body: some View {
        HStack(alignment: .top) {
            Spacer()
            
            VStack(spacing: 16) {
                GlassCircularButton(
                    iconName: cameraManager.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill",
                    iconColor: cameraManager.isFlashEnabled ? .yellow : .white
                ) {
                    cameraManager.toggleFlash()
                }
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) { @MainActor in
                    ZStack {
                        if hardwareOrchestrator.isGlassmorphismEnabled {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .frame(width: 50, height: 50)
                        } else {
                            Circle()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 50, height: 50)
                        }
                        
                        if let thumbnail = photoLibraryManager.latestThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 46, height: 46)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }
}
