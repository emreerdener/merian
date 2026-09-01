import Foundation

enum CarouselImageOrigin: Hashable {
    case user
    case reference
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
