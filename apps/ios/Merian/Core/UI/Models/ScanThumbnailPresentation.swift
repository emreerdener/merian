import Foundation

enum ScanThumbnailPlaceholderStyle: Sendable, Equatable {
    case archived
    case pendingReference(CapturedMediaKind)
    case unavailableReference(CapturedMediaKind)
}

struct ScanThumbnailPresentation: Sendable, Equatable {
    let imagePath: String?
    let fallbackImageUrl: String?
    let audioPath: String?
    let hasVideo: Bool
    let hasAudio: Bool
    let placeholderStyle: ScanThumbnailPlaceholderStyle
}

enum ScanThumbnailProjection {
    static func presentation(
        isBiological: Bool,
        isLocallyArchived: Bool,
        scientificName: String,
        coverImagePath: String?,
        referenceImageUrl: String?,
        mediaSnapshot: CapturedMediaSnapshot,
        canResolveReferenceImage: Bool? = nil
    ) -> ScanThumbnailPresentation {
        let fallbackURL = referenceImageUrl?.trimmedNonEmptyValue
        let mediaSummary = mediaSnapshot.summary
        let preferredVisualPath = coverImagePath?.trimmedNonEmptyValue
            ?? mediaSnapshot.primaryImagePath?.trimmedNonEmptyValue
        let hasStoredVisual = preferredVisualPath != nil
            || mediaSummary.hasImage
        let normalizedScientificName = scientificName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let inferredReferenceEligibility = isBiological
            && !isLocallyArchived
            && !normalizedScientificName.isEmpty
            && normalizedScientificName != "taxonomy unavailable"
            && normalizedScientificName != "unknown subject"
            && !hasStoredVisual
        let canResolveReference = canResolveReferenceImage
            ?? inferredReferenceEligibility
        let mediaKind = mediaSummary.preferredThumbnailKind ?? .other

        if hasStoredVisual {
            return ScanThumbnailPresentation(
                imagePath: preferredVisualPath,
                fallbackImageUrl: fallbackURL,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .archived
            )
        }

        let preferredAudioPath: String? = if mediaSummary.hasAudio,
                                             !mediaSummary.hasImage,
                                             !mediaSummary.hasDescription {
            mediaSnapshot.audioPaths.first?.trimmedNonEmptyValue
        } else {
            nil
        }
        if let preferredAudioPath {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackURL,
                audioPath: preferredAudioPath,
                hasVideo: false,
                hasAudio: true,
                placeholderStyle: fallbackURL != nil || canResolveReference
                    ? .pendingReference(mediaKind)
                    : .unavailableReference(mediaKind)
            )
        }

        if fallbackURL != nil {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: fallbackURL,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        if canResolveReference {
            return ScanThumbnailPresentation(
                imagePath: nil,
                fallbackImageUrl: nil,
                audioPath: nil,
                hasVideo: mediaSummary.hasVideo,
                hasAudio: mediaSummary.hasAudio,
                placeholderStyle: .pendingReference(mediaKind)
            )
        }

        return ScanThumbnailPresentation(
            imagePath: nil,
            fallbackImageUrl: nil,
            audioPath: nil,
            hasVideo: mediaSummary.hasVideo,
            hasAudio: mediaSummary.hasAudio,
            placeholderStyle: .unavailableReference(mediaKind)
        )
    }
}

extension LocalScanRecord {
    var scanThumbnailPresentation: ScanThumbnailPresentation {
        scanThumbnailPresentation(
            capturedMediaSnapshot: capturedMediaSnapshot
        )
    }

    func scanThumbnailPresentation(
        capturedMediaSnapshot mediaSnapshot: CapturedMediaSnapshot
    ) -> ScanThumbnailPresentation {
        ScanThumbnailProjection.presentation(
            isBiological: isBiological,
            isLocallyArchived: isLocallyArchived,
            scientificName: userIdentificationOverride?
                .trimmedNonEmptyValue
                ?? scientificName,
            coverImagePath: coverImagePath,
            referenceImageUrl: referenceImageUrl,
            mediaSnapshot: mediaSnapshot,
            canResolveReferenceImage: canResolveReferenceThumbnail
        )
    }
}
