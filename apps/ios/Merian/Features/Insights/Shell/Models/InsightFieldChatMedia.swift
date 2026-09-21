import Foundation

enum InsightFieldChatMedia {
    static func images(from media: ActiveScanMedia, wikipediaURL: String?) -> [FieldChatMedia] {
        var images = media.items.compactMap { item -> FieldChatMedia? in
            switch item {
            case .liveImage(let data): return .liveImage(data)
            case .image(let path): return .image(path: path)
            case .video(_, let fallback):
                switch fallback {
                case .liveImage(let data): return .liveImage(data)
                case .imagePath(let path): return .image(path: path, label: "Observation video still")
                case nil: return nil
                }
            case .audio, .description: return nil
            }
        }
        images += media.referenceState.urls.enumerated().compactMap { index, path in
            .image(
                path: path, label: "Species reference image",
                attribution: CarouselReferenceAttributionPolicy.label(
                    for: path, wikipediaURL: wikipediaURL, index: index
                )
            )
        }
        return FieldChatMedia.orderedUnique(images)
    }
}
