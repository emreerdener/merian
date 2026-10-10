import UIKit

/// One staged photograph. Its inference, display, thumbnail, and original
/// representations stay together so collection indexes cannot drift apart.
struct StagedImage {
    /// UI identity is separate from immutable history-media identity. Edits retain lineage only.
    enum ReanalysisProvenance: Equatable, Sendable {
        case added
        case original(analysisID: UUID, photo: ObservationHistoryPhotoReference)
        case editedOriginal(analysisID: UUID, photo: ObservationHistoryPhotoReference)

        var edited: Self {
            switch self {
            case .added: return .added
            case let .original(analysisID, photo), let .editedOriginal(analysisID, photo):
                return .editedOriginal(analysisID: analysisID, photo: photo)
            }
        }
    }

    let reanalysisProvenance: ReanalysisProvenance

    /// Tier-bounded WebP/JPEG payload used for inference, never UI rendering.
    let compressedData: Data

    /// Display-policy-bounded WebP/JPEG persisted for post-inference rendering.
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
        addedAt: Date = Date(),
        reanalysisProvenance: ReanalysisProvenance = .added
    ) {
        self.compressedData = compressedData
        self.displayData = displayData
        self.uiImage = uiImage
        self.original = original
        self.focusRegion = focusRegion
        self.addedAt = addedAt
        self.reanalysisProvenance = reanalysisProvenance
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
            addedAt: addedAt,
            reanalysisProvenance: compressedData != nil || original != nil ? reanalysisProvenance.edited : reanalysisProvenance
        )
    }

    func replacingFocusRegion(_ focusRegion: NormalizedImageFocusRegion?) -> StagedImage {
        StagedImage(
            compressedData: compressedData,
            displayData: displayData,
            uiImage: uiImage,
            original: original,
            focusRegion: focusRegion,
            addedAt: addedAt,
            reanalysisProvenance: reanalysisProvenance
        )
    }
}
