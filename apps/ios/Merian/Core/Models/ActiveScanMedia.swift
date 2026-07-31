import Foundation

/// The one retained still image that can replace an unavailable active video.
enum VideoFallbackImageSource: Equatable {
    case liveImage(Data)
    case imagePath(String)

    var imageIdentifier: String? {
        guard case .imagePath(let path) = self else { return nil }
        return path
    }
}

enum MediaItem: Equatable {
    /// A raw image buffer captured natively, held only during the active live asynchronous evaluation pipeline.
    case liveImage(Data)
    /// A persisted historical capture image path resolving natively via FileManager locally, or remotely via cloud URLs.
    case image(String)
    /// An absolute URL referencing an active or locally stored audio recording.
    /// Audio path resolution (temp vs docs directory) MUST be handled by the caller creating this item.
    case audio(String)
    /// A persisted historical capture video path resolving locally or remotely.
    /// Video path resolution (temp vs docs directory) MUST be handled by the caller creating this item.
    /// `fallbackImage` is a poster or one middle sampled frame, never a sampled-frame collection.
    case video(String, fallbackImage: VideoFallbackImageSource? = nil)
    /// A rich textual element carrying explicitly structured user description data or free-form context.
    case description(ObservationContext)
}

enum ReferenceState: Equatable {
    case empty
    case loading
    case loaded([String])
    
    var urls: [String] {
        if case .loaded(let urls) = self { return urls }
        return []
    }
}

enum ReferenceImageDeduplicationPolicy {
    static func filteredReferenceURLs(
        _ referenceURLs: [String],
        excluding mediaIdentifiers: [String]
    ) -> [String] {
        let excludedIdentities = Set(mediaIdentifiers.compactMap(mediaIdentity))
        guard !excludedIdentities.isEmpty else { return referenceURLs }

        return referenceURLs.filter { referenceURL in
            guard let identity = mediaIdentity(referenceURL) else { return true }
            return !excludedIdentities.contains(identity)
        }
    }

    private static func mediaIdentity(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return "path:\(trimmed)"
        }

        if host == "media.merian.app" || host.hasSuffix(".merian.app") {
            return "naturebook:\(host)\(components.percentEncodedPath)"
        }

        return "external:\(trimmed)"
    }
}

/// The unified structural representation of all multi-modal visual and audio data actively loaded into the interface.
/// Encapsulates discrete modalities (images, audio, context) dynamically into an ordered array sequence natively,
/// replacing structurally fragmented `hasLive` branching or multi-array property synchronization patterns.
struct ActiveScanMedia: Equatable {
    var items: [MediaItem] = []
    var referenceState: ReferenceState = .empty
    var focusRegionsBySourceIndex: [Int: NormalizedImageFocusRegion] = [:]

    init(
        items: [MediaItem] = [],
        referenceState: ReferenceState = .empty,
        focusRegionsBySourceIndex: [Int: NormalizedImageFocusRegion] = [:]
    ) {
        self.items = items
        self.referenceState = referenceState
        self.focusRegionsBySourceIndex = focusRegionsBySourceIndex
    }

    /// The consolidated length representing every active UI carousel node natively.
    var totalItems: Int {
        switch referenceState {
        case .empty: return items.count
        case .loading: return items.count + 1
        case .loaded(let urls): return items.count + urls.count
        }
    }
    
    var isEmpty: Bool {
        return items.isEmpty && referenceState == .empty
    }

    var withoutReferenceImages: ActiveScanMedia {
        ActiveScanMedia(
            items: items,
            referenceState: .empty,
            focusRegionsBySourceIndex: focusRegionsBySourceIndex
        )
    }

    func removingDuplicateReferenceImages(
        excluding additionalMediaIdentifiers: [String] = []
    ) -> ActiveScanMedia {
        guard case .loaded(let urls) = referenceState else { return self }

        let itemIdentifiers = items.flatMap { item -> [String] in
            switch item {
            case .image(let path):
                return [path]
            case .video(let path, let fallbackImage):
                return [path, fallbackImage?.imageIdentifier].compactMap { $0 }
            case .liveImage, .audio, .description:
                return []
            }
        }
        let filteredURLs = ReferenceImageDeduplicationPolicy.filteredReferenceURLs(
            urls,
            excluding: itemIdentifiers + additionalMediaIdentifiers
        )

        return ActiveScanMedia(
            items: items,
            referenceState: filteredURLs.isEmpty ? .empty : .loaded(filteredURLs),
            focusRegionsBySourceIndex: focusRegionsBySourceIndex
        )
    }

    var hasUserImage: Bool {
        liveImageData != nil || !imagePathsForUpload.isEmpty || !videoPaths.isEmpty
    }

    var liveImageData: Data? {
        for item in items {
            if case .liveImage(let data) = item { return data }
        }
        return nil
    }
    
    var imagePathsForUpload: [String] {
        var paths: [String] = []
        for item in items {
            if case .image(let path) = item { paths.append(path) }
        }
        return paths
    }

    var videoPaths: [String] {
        var paths: [String] = []
        for item in items {
            if case .video(let path, _) = item { paths.append(path) }
        }
        return paths
    }
}
