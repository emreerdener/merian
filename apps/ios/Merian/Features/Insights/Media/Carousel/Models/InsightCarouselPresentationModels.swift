import CoreGraphics
import Foundation

struct InsightImageGalleryItem: Identifiable, Equatable {
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

struct InsightImageGalleryPresentation: Identifiable, Equatable {
    let id: String
    let items: [InsightImageGalleryItem]
    let initialSelectedIndex: Int
    let initialVideoMuted: Bool

    init(
        items: [InsightImageGalleryItem],
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

enum CarouselImageOrigin: Hashable {
    case user
    case reference
}

enum InsightCarouselMediaInteractionPolicy {
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

enum CarouselReferenceAttributionPolicy {
    private enum Source {
        case wikipedia
        case gbif
        case merian

        var label: String {
            switch self {
            case .wikipedia:
                "Wikipedia"
            case .gbif:
                "GBIF"
            case .merian:
                "Naturebook"
            }
        }
    }

    static func label(
        for urlString: String,
        wikipediaURL: String?,
        index: Int
    ) -> String {
        source(
            for: urlString,
            wikipediaURL: wikipediaURL,
            index: index
        ).label
    }

    private static func source(
        for urlString: String,
        wikipediaURL: String?,
        index: Int
    ) -> Source {
        if let host = URL(string: urlString)?.host?.lowercased() {
            if host == "media.merian.app" || host.hasSuffix(".merian.app") {
                return .merian
            }

            if host.contains("wikipedia") || host.contains("wikimedia") {
                return .wikipedia
            }
        }

        let hasWikipediaURL = !(
            wikipediaURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true
        )
        if index == 0, hasWikipediaURL {
            return .wikipedia
        }

        return .gbif
    }
}
