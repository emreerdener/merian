import PhotosUI
import SwiftUI
import Photos

struct PhotoLibraryButton: View {
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
        .frame(width: 50, height: 50)
        .background(.ultraThinMaterial, in: Circle())
        .environment(\.colorScheme, .dark)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
    }
}
