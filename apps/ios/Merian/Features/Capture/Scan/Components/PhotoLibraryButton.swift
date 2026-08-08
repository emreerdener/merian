import Photos
import PhotosUI
import SwiftUI

struct PhotoLibraryButton: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let latestThumbnail: UIImage?
    var maxSelectionCount: Int = 1
    
    @State private var showPermissionPrompt = false
    @State private var authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    
    private var buttonContent: some View {
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
        .circularMaterialControl(colorScheme: .dark)
        .accessibilityIdentifier("PhotoLibraryButton")
    }
    
    var body: some View {
        Group {
            if authStatus == .notDetermined {
                Button {
                    showPermissionPrompt = true
                } label: {
                    buttonContent
                }
            } else {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: maxSelectionCount, matching: .images, photoLibrary: .shared()) {
                    buttonContent
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
        .sheet(isPresented: $showPermissionPrompt) {
            PhotoLibraryPermissionSheetView {
                authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                showPermissionPrompt = false
            }
            .presentationDetents([.height(350)])
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
    }
}
