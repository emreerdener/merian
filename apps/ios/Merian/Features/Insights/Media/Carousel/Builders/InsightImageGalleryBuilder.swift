import Foundation

struct InsightImageGalleryBuilder {
    static func buildItems(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?
    ) -> [InsightImageGalleryItem] {
        var items: [InsightImageGalleryItem] = []

        for item in activeMedia.items {
            switch item {
            case .liveImage(let data):
                items.append(InsightImageGalleryItem(
                    id: "liveImage-\(data.hashValue)",
                    source: .liveImage(data),
                    referenceAttributionLabel: nil
                ))
            case .image(let path):
                items.append(InsightImageGalleryItem(
                    id: "image-\(path)",
                    source: .imagePath(path),
                    referenceAttributionLabel: nil
                ))
            case .video(let path, _):
                items.append(InsightImageGalleryItem(
                    id: "video-\(path)",
                    source: .videoPath(path),
                    referenceAttributionLabel: nil
                ))
            case .audio, .description:
                break
            }
        }

        if case .loaded(let urls) = activeMedia.referenceState {
            for (index, urlString) in urls.enumerated() {
                let label = CarouselReferenceAttributionPolicy.label(
                    for: urlString,
                    wikipediaURL: referenceWikipediaUrl,
                    index: index
                )
                items.append(InsightImageGalleryItem(
                    id: "reference-\(urlString)",
                    source: .referenceURL(urlString),
                    referenceAttributionLabel: label
                ))
            }
        }

        return items
    }

    static func presentation(
        items: [InsightImageGalleryItem],
        selectedCarouselPageID: String?,
        isVideoMuted: Bool = true
    ) -> InsightImageGalleryPresentation? {
        guard let selectedCarouselPageID,
              let selectedIndex = items.firstIndex(where: {
                  $0.id == selectedCarouselPageID
              }) else {
            return nil
        }
        return InsightImageGalleryPresentation(
            items: items,
            initialSelectedIndex: selectedIndex,
            initialVideoMuted: isVideoMuted
        )
    }

    static func presentation(
        for activeMedia: ActiveScanMedia,
        referenceWikipediaUrl: String?,
        selectedCarouselPageID: String?,
        orderedCarouselPageIDs: [String]? = nil,
        isVideoMuted: Bool = true
    ) -> InsightImageGalleryPresentation? {
        guard let selectedCarouselPageID else { return nil }

        let allItems = buildItems(
            for: activeMedia,
            referenceWikipediaUrl: referenceWikipediaUrl
        )
        let itemsByID = Dictionary(
            allItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let items = orderedCarouselPageIDs.map { pageIDs in
            pageIDs.compactMap { itemsByID[$0] }
        } ?? allItems
        return presentation(
            items: items,
            selectedCarouselPageID: selectedCarouselPageID,
            isVideoMuted: isVideoMuted
        )
    }
}
