import Foundation

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
    case video(String)
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

/// The unified structural representation of all multi-modal visual and audio data actively loaded into the interface.
/// Encapsulates discrete modalities (images, audio, context) dynamically into an ordered array sequence natively,
/// replacing structurally fragmented `hasLive` branching or multi-array property synchronization patterns.
struct ActiveScanMedia: Equatable {
    var items: [MediaItem] = []
    var referenceState: ReferenceState = .empty

    init(items: [MediaItem] = [], referenceState: ReferenceState = .empty) {
        self.items = items
        self.referenceState = referenceState
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
            if case .video(let path) = item { paths.append(path) }
        }
        return paths
    }
}
