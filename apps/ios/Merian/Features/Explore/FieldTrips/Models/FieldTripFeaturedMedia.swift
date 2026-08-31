import CoreGraphics
import Foundation

enum FieldTripFeaturedMediaSource: Equatable {
    case userImage(path: String)
    case userVideo(path: String, posterPath: String)
    case reference(SpeciesDictionaryReferenceImage)

    var posterPath: String {
        switch self {
        case .userImage(let path):
            path
        case .userVideo(_, let posterPath):
            posterPath
        case .reference(let image):
            image.url
        }
    }

    var isVideo: Bool {
        if case .userVideo = self { return true }
        return false
    }

    var isReference: Bool {
        if case .reference = self { return true }
        return false
    }

    var inlineAttributionLabel: String? {
        guard case .reference(let image) = self else { return nil }
        return image.source.label
    }

    var inlineContributorAttributionLabel: String? {
        guard case .reference(let image) = self,
              let username = image.naturebookAuthorUsername else { return nil }
        return "@\(username)"
    }

    var fullscreenAttributionLabel: String? {
        guard case .reference(let image) = self else { return nil }
        return image.fullscreenAttributionLabel
    }

    var localPath: String? {
        isReference ? nil : posterPath
    }

    var fallbackImageURL: String? {
        isReference ? posterPath : nil
    }

    var gallerySource: InsightImageGalleryItem.Source {
        switch self {
        case .userImage(let path):
            .imagePath(path)
        case .userVideo(let path, _):
            .videoPath(path)
        case .reference(let image):
            .referenceURL(image.url)
        }
    }
}

struct FieldTripFeaturedMediaPageReuseIdentity: Hashable {
    let id: String
    let isReference: Bool
}

struct FieldTripFeaturedMediaItem: Identifiable, Equatable {
    let id: String
    let scanId: String?
    let levelId: String
    let levelNumber: Int
    let levelTitle: String
    let checklistOrder: Int
    let goalTitle: String
    let completedCommonName: String?
    let referenceSpecies: FieldTripReferenceSpecies?
    let source: FieldTripFeaturedMediaSource

    var pageReuseIdentity: FieldTripFeaturedMediaPageReuseIdentity {
        FieldTripFeaturedMediaPageReuseIdentity(
            id: id,
            isReference: source.isReference
        )
    }

    var accessibilityLabel: String {
        var parts = [levelTitle, goalTitle]
        if source.isReference {
            if let commonName = referenceSpecies?.commonName.fieldTripFeaturedNonBlank,
               commonName.caseInsensitiveCompare(goalTitle) != .orderedSame {
                parts.append("Example: \(commonName)")
            }
            parts.append("Reference photo from \(source.inlineAttributionLabel ?? "reference source")")
        } else {
            if let completedCommonName = completedCommonName?.fieldTripFeaturedNonBlank,
               completedCommonName.caseInsensitiveCompare(goalTitle) != .orderedSame {
                parts.append(completedCommonName)
            }
            parts.append(source.isVideo ? "Your video" : "Your photo")
        }
        return parts.joined(separator: ", ")
    }

    var galleryItem: InsightImageGalleryItem {
        InsightImageGalleryItem(
            id: id,
            source: source.gallerySource,
            referenceAttributionLabel: source.fullscreenAttributionLabel,
            accessibilityLabel: accessibilityLabel
        )
    }
}

enum FieldTripFeaturedMediaBuilder {
    static func candidates(
        for template: FieldTripTemplate,
        localScansById: [String: LocalScanRecord],
        excluding unavailableSourceIdentifiers: Set<String> = []
    ) -> [FieldTripFeaturedMediaItem] {
        var seenScanIds: Set<String> = []
        var candidates: [FieldTripFeaturedMediaItem] = []

        for level in template.levels.sorted(by: levelSort) {
            for (checklistOrder, item) in level.items.enumerated() {
                var scanId: String?
                var source: FieldTripFeaturedMediaSource?

                if item.isCompleted,
                   let completedScanId = item.completedScanId?.fieldTripFeaturedNonBlank,
                   !seenScanIds.contains(completedScanId),
                   let scan = localScansById[completedScanId],
                   !scan.isLocallyArchived,
                   let userSource = featuredUserSource(for: scan) {
                    seenScanIds.insert(completedScanId)
                    scanId = completedScanId
                    if !unavailableSourceIdentifiers.contains(userSource.posterPath) {
                        source = userSource
                    }
                }

                if source == nil {
                    source = featuredReferenceSource(
                        for: item,
                        excluding: unavailableSourceIdentifiers
                    )
                }

                guard let source else { continue }
                candidates.append(FieldTripFeaturedMediaItem(
                    id: stableId(itemId: item.id),
                    scanId: scanId,
                    levelId: level.id,
                    levelNumber: level.levelNumber,
                    levelTitle: level.title,
                    checklistOrder: checklistOrder,
                    goalTitle: item.prompt,
                    completedCommonName: item.completedCommonName,
                    referenceSpecies: item.referenceSpecies,
                    source: source
                ))
            }
        }

        return candidates
    }

    private static func featuredUserSource(
        for scan: LocalScanRecord
    ) -> FieldTripFeaturedMediaSource? {
        for item in scan.capturedMediaSnapshot.items {
            switch item {
            case .image(let reference):
                guard let path = reference.serializedPath.fieldTripFeaturedNonBlank,
                      !isSpeciesReferenceImage(path, for: scan) else {
                    continue
                }
                return .userImage(path: path)
            case .video(let reference):
                guard let videoPath = (
                    reference.resolvedLocalPath ?? reference.serializedPath
                ).fieldTripFeaturedNonBlank,
                    let posterPath = reference.resolvedThumbnailPath?.fieldTripFeaturedNonBlank,
                    !isSpeciesReferenceImage(posterPath, for: scan) else {
                    continue
                }
                return .userVideo(path: videoPath, posterPath: posterPath)
            case .audio, .description:
                continue
            }
        }

        guard let coverImagePath = scan.coverImagePath?.fieldTripFeaturedNonBlank,
              !isSpeciesReferenceImage(coverImagePath, for: scan) else {
            return nil
        }
        return .userImage(path: coverImagePath)
    }

    private static func featuredReferenceSource(
        for item: FieldTripChecklistItem,
        excluding unavailableSourceIdentifiers: Set<String>
    ) -> FieldTripFeaturedMediaSource? {
        guard let referenceSpecies = item.referenceSpecies else { return nil }
        let sourceOrder: [SpeciesDictionaryReferenceImage.Source] = [
            .merian,
            .wikipedia,
            .gbif
        ]

        for source in sourceOrder {
            if let image = referenceSpecies.referenceImages.first(where: {
                $0.source == source
                    && ExternalReferenceImagePolicy.isAllowed($0.url)
                    && !unavailableSourceIdentifiers.contains($0.url)
            }) {
                return .reference(image)
            }
        }
        return nil
    }

    private static func isSpeciesReferenceImage(
        _ path: String,
        for scan: LocalScanRecord
    ) -> Bool {
        guard let referenceImageUrl = scan.referenceImageUrl?.fieldTripFeaturedNonBlank else {
            return false
        }
        return path == referenceImageUrl
    }

    private static func levelSort(_ lhs: FieldTripLevel, _ rhs: FieldTripLevel) -> Bool {
        if lhs.levelNumber != rhs.levelNumber {
            return lhs.levelNumber < rhs.levelNumber
        }
        return lhs.id < rhs.id
    }

    private static func stableId(itemId: String) -> String {
        "field-trip-featured-goal:\(itemId)"
    }
}

enum FieldTripFeaturedMediaSelection {
    static let maximumItemCount = 6

    static func items(
        from candidates: [FieldTripFeaturedMediaItem],
        activeLevelId: String?,
        maximumCount: Int = maximumItemCount
    ) -> [FieldTripFeaturedMediaItem] {
        let limit = max(0, maximumCount)
        guard limit > 0, let activeLevelId else { return [] }

        return Array(
            candidates
                .filter { $0.levelId == activeLevelId }
                .sorted(by: candidateSort)
                .prefix(limit)
        )
    }

    private static func candidateSort(
        _ lhs: FieldTripFeaturedMediaItem,
        _ rhs: FieldTripFeaturedMediaItem
    ) -> Bool {
        if lhs.checklistOrder != rhs.checklistOrder {
            return lhs.checklistOrder < rhs.checklistOrder
        }
        return lhs.id < rhs.id
    }
}

enum FieldTripFeaturedMediaPresentation {
    static func selectedIndex(
        preserving selectedItemId: String?,
        previousSelectedIndex: Int,
        in items: [FieldTripFeaturedMediaItem]
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        if let selectedItemId,
           let preservedIndex = items.firstIndex(where: { $0.id == selectedItemId }) {
            return preservedIndex
        }
        return max(0, min(previousSelectedIndex, items.count - 1))
    }

    static func galleryPresentation(
        for items: [FieldTripFeaturedMediaItem],
        selectedItemId: String?
    ) -> InsightImageGalleryPresentation? {
        guard !items.isEmpty else { return nil }
        let selectedIndex = items.firstIndex(where: { $0.id == selectedItemId }) ?? 0
        return InsightImageGalleryPresentation(
            items: items.map(\.galleryItem),
            initialSelectedIndex: selectedIndex,
            initialVideoMuted: true
        )
    }
}

enum FieldTripFeaturedMediaLayout {
    static let scrollCoordinateSpace = "FieldTripDetailScrollSpace"
    static let contentOverlap: CGFloat = 32
    static let contentTopSpacing: CGFloat = 24
    static let overlayInset: CGFloat = 14
    static let overlayBottomInset = contentOverlap + overlayInset
    static let bleedBuffer: CGFloat = 50

    static func underlapsNavigationBar(
        featuredItemCount: Int
    ) -> Bool {
        featuredItemCount > 0
    }

    static func heroHeight(
        baseHeight: CGFloat,
        scrollOffset: CGFloat
    ) -> CGFloat {
        baseHeight + max(scrollOffset, 0) + bleedBuffer
    }

    static func heroOffset(scrollOffset: CGFloat) -> CGFloat {
        -(max(scrollOffset, 0) + bleedBuffer)
    }
}

private extension String {
    var fieldTripFeaturedNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
