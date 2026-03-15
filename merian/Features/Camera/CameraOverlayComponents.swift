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
                Button(action: {
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
                
                let thumb = photoLibraryManager.latestThumbnail
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
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
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }
}
