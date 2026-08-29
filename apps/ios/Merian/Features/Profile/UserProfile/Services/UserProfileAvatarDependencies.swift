import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct UserProfileAvatarDependencies {
    let prepareCropImage: @MainActor (
        _ item: PhotosPickerItem
    ) async throws -> IdentifiableImage?
    let prepareUpload: @Sendable (
        _ croppedData: Data
    ) async throws -> PreparedProfileAvatar

    static let live = Self(
        prepareCropImage: { item in
            guard let wrapper = try await item.loadTransferable(
                type: ImageFileWrapper.self
            ) else {
                return nil
            }

            let fileURL = wrapper.url
            defer { try? FileManager.default.removeItem(at: fileURL) }

            let preview = try await MediaPreparationActor.shared
                .preparePreviewImage(
                    fileURL: fileURL,
                    maxSize: MerianConfig.displayImageMaxSize
                )
            return IdentifiableImage(
                image: UIImage(cgImage: preview.cgImage)
            )
        },
        prepareUpload: { croppedData in
            try await DetachedWork.value(
                priority: .userInitiated,
                category: .imagePreparation
            ) {
                try ProfileAvatarImagePreparer.prepare(
                    croppedData: croppedData
                )
            }
        }
    )
}
