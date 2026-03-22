import SwiftUI
import PhotosUI

struct PhotoLibraryButton: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let latestThumbnail: UIImage?
    
    var body: some View {
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
    }
}
