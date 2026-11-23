import UIKit

/// One staged photograph. Its inference, display, thumbnail, and original
/// representations stay together so collection indexes cannot drift apart.
struct StagedImage {
    /// Presentation provenance only; never a file or submission capability.
    enum ReviewBasis: Equatable {
        case unproven
        case nativeOriginal(SharedMediaNativePreparationRecipe)
        case preparedArtifact(sha256: String)
        case squareCropSource
    }
    let reviewBasis: ReviewBasis

    var hasPreparedReviewIdentity: Bool {
        guard case let .preparedArtifact(sha256) = reviewBasis else { return false }
        return original.lastCropDisplaySize == nil && original.lastCropQuarterTurns == 0
            && original.lastCropScale == 1 && original.lastCropOffset == .zero
            && SharedMediaAcquisitionEncoding.digest(compressedData) == sha256
    }

    var startsWithFullAspectReview: Bool {
        switch reviewBasis {
        case let .nativeOriginal(recipe): return recipe.format != .cameraStill && recipe.cropDisplaySize == nil
        case .preparedArtifact: return hasPreparedReviewIdentity
        case .unproven, .squareCropSource: return false
        }
    }
    /// UI identity is separate from immutable history-media identity. Edits retain lineage only.
    enum ReanalysisProvenance: Equatable, Sendable {
        case added
        case original(analysisID: UUID, photo: ObservationHistoryPhotoReference)
        case editedOriginal(analysisID: UUID, photo: ObservationHistoryPhotoReference)
        case retained(ObservationReanalysisRetainedInput.Photo, edited: Bool)

        var edited: Self {
            switch self {
            case .added: return .added
            case let .retained(photo, _): return .retained(photo, edited: true)
            case let .original(analysisID, photo), let .editedOriginal(analysisID, photo):
                return .editedOriginal(analysisID: analysisID, photo: photo)
            }
        }
    }

    let photoOriginalReference: PhotoOriginalReference?
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
        reanalysisProvenance: ReanalysisProvenance = .added,
        photoOriginalReference: PhotoOriginalReference? = nil,
        reviewBasis: ReviewBasis = .unproven
    ) {
        self.photoOriginalReference = photoOriginalReference
        self.compressedData = compressedData
        self.displayData = displayData
        self.uiImage = uiImage
        self.original = original
        self.focusRegion = focusRegion
        self.addedAt = addedAt
        self.reanalysisProvenance = reanalysisProvenance
        self.reviewBasis = reviewBasis
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
            reanalysisProvenance: compressedData != nil || original != nil ? reanalysisProvenance.edited : reanalysisProvenance,
            photoOriginalReference: photoOriginalReference,
            reviewBasis: original.map { $0.image === self.original.image } == false ? .unproven : reviewBasis
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
            reanalysisProvenance: reanalysisProvenance,
            photoOriginalReference: photoOriginalReference,
            reviewBasis: reviewBasis
        )
    }
}
