import Foundation

enum ExploreFieldChatMedia {
    static func images(items: [ExploreMediaItem], heroImageURL: String) -> [FieldChatMedia] {
        var images = ExplorePostMediaCarouselPolicy.orderedItems(
            items, fallbackImageUrl: heroImageURL
        ).compactMap { item -> FieldChatMedia? in
            switch item.kind {
            case .image: return .image(path: item.url)
            case .video:
                return item.posterImageUrl(fallback: heroImageURL).flatMap {
                    .image(path: $0, label: "Observation video still")
                }
            case .audio: return nil
            }
        }
        if let hero = FieldChatMedia.image(path: heroImageURL) {
            images.append(hero)
        }
        return FieldChatMedia.orderedUnique(images, featuredPath: heroImageURL)
    }
}
