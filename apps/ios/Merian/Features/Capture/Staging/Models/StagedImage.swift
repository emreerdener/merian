import UIKit

/// One staged photograph. Its inference, display, thumbnail, and original
/// representations stay together so collection indexes cannot drift apart.
struct StagedImage {
    /// 1024 px WebP/JPEG payload used for inference, never UI rendering.
    let compressedData: Data

    /// 2048 px WebP/JPEG persisted for crisp post-inference rendering.
    let displayData: Data

    /// Decoded thumbnail rendered in the active capture toolbar.
    let uiImage: UIImage

    /// Full-resolution crop source and shutter-time environment context.
    let original: IdentifiableImage

    /// Transient focus metadata for the final post-crop inference image.
    let focusRegion: NormalizedImageFocusRegion?

    /// Chronological insertion time shared with every staged modality.
    var addedAt: Date = Date()

    init(
        compressedData: Data,
        displayData: Data,
        uiImage: UIImage,
        original: IdentifiableImage,
        focusRegion: NormalizedImageFocusRegion? = nil,
        addedAt: Date = Date()
    ) {
        self.compressedData = compressedData
        self.displayData = displayData
        self.uiImage = uiImage
        self.original = original
        self.focusRegion = focusRegion
        self.addedAt = addedAt
    }

    func replacing(
        compressedData: Data? = nil,
        displayData: Data? = nil,
        uiImage: UIImage? = nil,
        original: IdentifiableImage? = nil
    ) -> StagedImage {
        StagedImage(
            compressedData: compressedData ?? self.compressedData,
            displayData: displayData ?? self.displayData,
            uiImage: uiImage ?? self.uiImage,
            original: original ?? self.original,
            focusRegion: focusRegion,
            addedAt: addedAt
        )
    }

    func replacingFocusRegion(_ focusRegion: NormalizedImageFocusRegion?) -> StagedImage {
        StagedImage(
            compressedData: compressedData,
            displayData: displayData,
            uiImage: uiImage,
            original: original,
            focusRegion: focusRegion,
            addedAt: addedAt
        )
    }
}
