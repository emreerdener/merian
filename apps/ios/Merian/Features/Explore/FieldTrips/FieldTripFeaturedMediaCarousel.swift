import Foundation
import SwiftUI

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

    var imageOrigin: CarouselImageOrigin {
        isReference ? .reference : .user
    }

    var inlineAttributionLabel: String? {
        guard case .reference(let image) = self else { return nil }
        return image.source.label
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
        maximumCount: Int = maximumItemCount
    ) -> [FieldTripFeaturedMediaItem] {
        let limit = max(0, maximumCount)
        guard limit > 0 else { return [] }

        let grouped = Dictionary(grouping: candidates, by: \.levelNumber)
        let levelNumbers = grouped.keys.sorted()
        let levelBuckets = levelNumbers.map { levelNumber in
            (grouped[levelNumber] ?? []).sorted(by: candidateSort)
        }
        var nextIndices = Array(repeating: 0, count: levelBuckets.count)
        var selectedItems: [FieldTripFeaturedMediaItem] = []

        while selectedItems.count < limit {
            var appendedInRound = false

            for bucketIndex in levelBuckets.indices where selectedItems.count < limit {
                let itemIndex = nextIndices[bucketIndex]
                guard levelBuckets[bucketIndex].indices.contains(itemIndex) else { continue }
                selectedItems.append(levelBuckets[bucketIndex][itemIndex])
                nextIndices[bucketIndex] += 1
                appendedInRound = true
            }

            guard appendedInRound else { break }
        }

        return selectedItems
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
    static func underlapsNavigationBar(
        isGoalsSelected: Bool,
        featuredItemCount: Int
    ) -> Bool {
        isGoalsSelected && featuredItemCount > 0
    }
}

struct FieldTripFeaturedMediaCarousel: View {
    let items: [FieldTripFeaturedMediaItem]
    let onMediaLoadFailed: (String) -> Void
    let onOpenViewer: (String) -> Void

    @State private var selectedIndex = 0
    @State private var selectedItemId: String?

    private var carouselPages: [CarouselPageItem] {
        items.map { item in
            CarouselPageItem(
                id: item.id,
                mediaKind: .visual,
                view: AnyView(page(for: item)),
                imageIdentifier: item.source.posterPath,
                imageOrigin: item.source.imageOrigin,
                referenceAttributionLabel: item.source.fullscreenAttributionLabel,
                galleryItem: item.galleryItem
            )
        }
    }

    var body: some View {
        GeometryReader { _ in
            NativePageCarousel(selectedIndex: $selectedIndex, pages: carouselPages)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipped()
                .overlay(alignment: .bottom) {
                    MediaCarouselPaginationDots(
                        pageCount: items.count,
                        selectedIndex: selectedIndex,
                        bottomPadding: 14,
                        accessibilityNoun: "Featured image"
                    )
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { _ in
                        openSelectedPage()
                    }
                )
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .onAppear(perform: reconcileSelection)
        .onChange(of: selectedIndex) { _, newValue in
            guard let item = items[safe: newValue] else { return }
            selectedItemId = item.id
        }
        .onChange(of: items.map(\.id)) { _, _ in
            reconcileSelection()
        }
        .accessibilityIdentifier("FieldTripFeaturedMediaCarousel")
    }

    private func page(for item: FieldTripFeaturedMediaItem) -> some View {
        ZStack {
            AsyncLocalImageView(
                path: item.source.localPath,
                fallbackImageUrl: item.source.fallbackImageURL,
                contentMode: .fill,
                unavailableContext: .originalPhoto,
                onImageLoadFailed: {
                    onMediaLoadFailed(item.source.posterPath)
                }
            )

            if item.source.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .accessibilityHidden(true)
            }

            if let attributionLabel = item.source.inlineAttributionLabel {
                Text(attributionLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.black.opacity(0.28))
                    }
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14)
                    .padding(.bottom, 40)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("Opens the full-screen media viewer")
        .accessibilityIdentifier("FieldTripFeaturedMediaPage_\(item.id)")
        .accessibilityAction {
            onOpenViewer(item.id)
        }
    }

    private func openSelectedPage() {
        guard let item = items[safe: selectedIndex] else { return }
        onOpenViewer(item.id)
    }

    private func reconcileSelection() {
        let nextIndex = FieldTripFeaturedMediaPresentation.selectedIndex(
            preserving: selectedItemId,
            previousSelectedIndex: selectedIndex,
            in: items
        )
        selectedIndex = nextIndex
        selectedItemId = items[safe: nextIndex]?.id
    }
}

private extension String {
    var fieldTripFeaturedNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
