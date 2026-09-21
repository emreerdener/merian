import Foundation

/// Presentation-only images. These values never enter the chat endpoint or transcript.
struct FieldChatMedia: Equatable, Identifiable {
    enum Source: Equatable {
        case path(String)
        case liveImage(Data)
    }

    let id: String
    let source: Source
    let accessibilityLabel: String
    let attribution: String?

    static func image(
        path: String,
        label: String = "Observation photo",
        attribution: String? = nil
    ) -> Self? {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return Self(id: path, source: .path(path), accessibilityLabel: label, attribution: attribution)
    }

    static func liveImage(_ data: Data) -> Self? {
        guard !data.isEmpty else { return nil }
        return Self(
            id: "live-\(data.hashValue)", source: .liveImage(data),
            accessibilityLabel: "Observation photo", attribution: nil
        )
    }

    static func orderedUnique(_ items: [Self], featuredPath: String? = nil) -> [Self] {
        var result: [Self] = []
        for item in items {
            guard !result.contains(where: { $0.id == item.id || $0.source == item.source }) else { continue }
            if case .path(let path) = item.source {
                let existingPaths = result.compactMap { media -> String? in
                    guard case .path(let path) = media.source else { return nil }
                    return path
                }
                guard !ReferenceImageDeduplicationPolicy.filteredReferenceURLs(
                    [path], excluding: existingPaths
                ).isEmpty else { continue }
            }
            result.append(item)
        }
        if let featuredPath = featuredPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           let index = result.firstIndex(where: { item in
               guard case .path(let path) = item.source else { return false }
               return ReferenceImageDeduplicationPolicy.filteredReferenceURLs(
                   [featuredPath], excluding: [path]
               ).isEmpty
           }) {
            result.insert(result.remove(at: index), at: 0)
        }
        return result
    }
}

enum FieldChatImageNavigation {
    static func swipeOffset(horizontal: Double, vertical: Double, isRightToLeft: Bool) -> Int? {
        guard abs(horizontal) >= 35, abs(horizontal) > abs(vertical) else { return nil }
        let forward = isRightToLeft ? horizontal > 0 : horizontal < 0
        return forward ? 1 : -1
    }
}
