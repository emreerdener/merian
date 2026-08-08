import Foundation
import SwiftUI

enum FieldTripFeaturedMediaSource: Equatable {
    case image(path: String)
    case video(path: String, posterPath: String)

    var posterPath: String {
        switch self {
        case .image(let path):
            path
        case .video(_, let posterPath):
            posterPath
        }
    }

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }

    var gallerySource: InsightImageGalleryItem.Source {
        switch self {
        case .image(let path):
            .imagePath(path)
        case .video(let path, _):
            .videoPath(path)
        }
    }
}

struct FieldTripFeaturedMediaItem: Identifiable, Equatable {
    let id: String
    let scanId: String
    let levelId: String
    let levelNumber: Int
    let levelTitle: String
    let checklistOrder: Int
    let goalTitle: String
    let completedCommonName: String?
    let source: FieldTripFeaturedMediaSource
    let imageQualityScore: Int?
    let capturedAt: Date

    var accessibilityLabel: String {
        var parts = [levelTitle, goalTitle]
        if let completedCommonName = completedCommonName?.fieldTripFeaturedNonBlank,
           completedCommonName.caseInsensitiveCompare(goalTitle) != .orderedSame {
            parts.append(completedCommonName)
        }
        parts.append(source.isVideo ? "Video" : "Photo")
        return parts.joined(separator: ", ")
    }

    var galleryItem: InsightImageGalleryItem {
        InsightImageGalleryItem(
            id: id,
            source: source.gallerySource,
            referenceAttributionLabel: nil,
            accessibilityLabel: accessibilityLabel
        )
    }
}

enum FieldTripFeaturedMediaBuilder {
    static func candidates(
        for template: FieldTripTemplate,
        localScansById: [String: LocalScanRecord]
    ) -> [FieldTripFeaturedMediaItem] {
        var seenScanIds: Set<String> = []
        var candidates: [FieldTripFeaturedMediaItem] = []

        for level in template.levels.sorted(by: levelSort) {
            for (checklistOrder, item) in level.items.enumerated() {
                guard item.isCompleted,
                      let scanId = item.completedScanId?.fieldTripFeaturedNonBlank,
                      !seenScanIds.contains(scanId),
                      let scan = localScansById[scanId],
                      !scan.isLocallyArchived,
                      let source = featuredSource(for: scan) else {
                    continue
                }

                seenScanIds.insert(scanId)
                candidates.append(FieldTripFeaturedMediaItem(
                    id: stableId(scanId: scanId),
                    scanId: scanId,
                    levelId: level.id,
                    levelNumber: level.levelNumber,
                    levelTitle: level.title,
                    checklistOrder: checklistOrder,
                    goalTitle: item.prompt,
                    completedCommonName: item.completedCommonName,
                    source: source,
                    imageQualityScore: scan.imageQualityScore,
                    capturedAt: scan.captureDate ?? scan.timestamp
                ))
            }
        }

        return candidates
    }

    private static func featuredSource(for scan: LocalScanRecord) -> FieldTripFeaturedMediaSource? {
        for item in scan.capturedMediaSnapshot.items {
            switch item {
            case .image(let reference):
                guard let path = reference.serializedPath.fieldTripFeaturedNonBlank,
                      !isSpeciesReferenceImage(path, for: scan) else {
                    continue
                }
                return .image(path: path)
            case .video(let reference):
                guard let videoPath = (
                    reference.resolvedLocalPath ?? reference.serializedPath
                ).fieldTripFeaturedNonBlank,
                    let posterPath = reference.resolvedThumbnailPath?.fieldTripFeaturedNonBlank,
                    !isSpeciesReferenceImage(posterPath, for: scan) else {
                    continue
                }
                return .video(path: videoPath, posterPath: posterPath)
            case .audio, .description:
                continue
            }
        }

        guard let coverImagePath = scan.coverImagePath?.fieldTripFeaturedNonBlank,
              !isSpeciesReferenceImage(coverImagePath, for: scan) else {
            return nil
        }
        return .image(path: coverImagePath)
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

    private static func stableId(scanId: String) -> String {
        "field-trip-featured:\(scanId)"
    }
}

enum FieldTripFeaturedMediaSelection {
    static let maximumItemCount = 6

    static func items(
        from candidates: [FieldTripFeaturedMediaItem],
        excluding failedItemIds: Set<String> = [],
        maximumCount: Int = maximumItemCount
    ) -> [FieldTripFeaturedMediaItem] {
        let limit = max(0, maximumCount)
        guard limit > 0 else { return [] }

        let availableCandidates = candidates.filter { !failedItemIds.contains($0.id) }
        let grouped = Dictionary(grouping: availableCandidates, by: \.levelNumber)
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
        let lhsQuality = lhs.imageQualityScore ?? Int.min
        let rhsQuality = rhs.imageQualityScore ?? Int.min
        if lhsQuality != rhsQuality {
            return lhsQuality > rhsQuality
        }
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt > rhs.capturedAt
        }
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
                imageOrigin: .user,
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
                path: item.source.posterPath,
                fallbackImageUrl: nil,
                contentMode: .fill,
                unavailableContext: .originalPhoto,
                onImageLoadFailed: {
                    onMediaLoadFailed(item.id)
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
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityHint("Opens the full-screen media viewer")
        .accessibilityIdentifier("FieldTripFeaturedMediaPage_\(item.scanId)")
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
