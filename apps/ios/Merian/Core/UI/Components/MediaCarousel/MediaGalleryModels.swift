import CoreGraphics
import Foundation

struct MediaGalleryItem: Identifiable, Equatable {
    enum Source: Equatable {
        case liveImage(Data)
        case imagePath(String)
        case videoPath(String)
        case referenceURL(String)

        var isVideo: Bool {
            if case .videoPath = self { return true }
            return false
        }
    }

    let id: String
    let source: Source
    let referenceAttributionLabel: String?
    let accessibilityLabel: String?

    init(
        id: String,
        source: Source,
        referenceAttributionLabel: String?,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.source = source
        self.referenceAttributionLabel = referenceAttributionLabel
        self.accessibilityLabel = accessibilityLabel
    }
}

struct MediaGalleryPresentation: Identifiable, Equatable {
    let id: String
    let items: [MediaGalleryItem]
    let initialSelectedIndex: Int
    let initialVideoMuted: Bool

    init(
        items: [MediaGalleryItem],
        initialSelectedIndex: Int,
        initialVideoMuted: Bool = true
    ) {
        self.items = items
        self.initialSelectedIndex = initialSelectedIndex
        self.initialVideoMuted = initialVideoMuted
        self.id = "\(items.map(\.id).joined(separator: "|"))#\(initialSelectedIndex)"
    }
}

enum CarouselMediaKind: Equatable {
    case visual
    case audio
    case video
    case description
}

enum MediaCarouselInteractionPolicy {
    static let centerPlaybackHitSize: CGFloat = 96

    static func isCenterPlaybackTap(
        location: CGPoint,
        containerSize: CGSize,
        mediaKind: CarouselMediaKind
    ) -> Bool {
        guard case .video = mediaKind else { return false }

        let hitSize = centerPlaybackHitSize
        let hitFrame = CGRect(
            x: (containerSize.width - hitSize) / 2,
            y: (containerSize.height - hitSize) / 2,
            width: hitSize,
            height: hitSize
        )
        return hitFrame.contains(location)
    }
}
