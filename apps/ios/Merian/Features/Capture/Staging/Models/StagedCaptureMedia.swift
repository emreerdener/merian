import Foundation

/// A staged audio recording track with its captured file path.
struct StagedAudio {
    /// Draft-local identity survives collection edits; never a submission identity.
    let id: UUID
    let filePath: String
    /// Listening preference only; never serialized into scan evidence.
    var prefersBoostedPreview: Bool = false
    var addedAt: Date = Date()
    #if DEBUG && targetEnvironment(simulator)
    var debugReplayProfile: DebugIdentificationReplayProfile?
    #endif

    init(filePath: String, prefersBoostedPreview: Bool = false, addedAt: Date = Date(), id: UUID = UUID()) {
        self.id = id; self.filePath = filePath
        self.prefersBoostedPreview = prefersBoostedPreview; self.addedAt = addedAt
    }
    #if DEBUG && targetEnvironment(simulator)
    init(filePath: String, prefersBoostedPreview: Bool = false, addedAt: Date = Date(),
         debugReplayProfile: DebugIdentificationReplayProfile?, id: UUID = UUID()) {
        self.init(filePath: filePath, prefersBoostedPreview: prefersBoostedPreview, addedAt: addedAt, id: id)
        self.debugReplayProfile = debugReplayProfile
    }
    #endif
}

/// A staged short video clip with sampled frame images used for AI inference.
struct StagedVideo {
    let id: UUID
    let filePath: String
    let sampledImages: [StagedImage]
    let audioFilePath: String?
    /// Immutable draft-owned editing source; never an accepted-library file.
    let originalFilePath: String?
    let composingCenter: CGFloat
    let framing: CaptureVideoFraming?
    let allowsReframing: Bool
    var addedAt: Date = Date()

    init(
        filePath: String,
        sampledImages: [StagedImage],
        audioFilePath: String? = nil,
        addedAt: Date = Date(),
        id: UUID = UUID(), originalFilePath: String? = nil,
        composingCenter: CGFloat = 0.5, framing: CaptureVideoFraming? = nil, allowsReframing: Bool = true
    ) {
        self.id = id
        self.originalFilePath = originalFilePath
        self.composingCenter = composingCenter
        self.framing = framing
        self.allowsReframing = allowsReframing
        self.filePath = filePath
        self.sampledImages = sampledImages
        self.audioFilePath = audioFilePath
        self.addedAt = addedAt
    }

    /// History staging uses a Documents basename; camera staging uses an absolute path.
    static func localURL(for path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appendingPathComponent(path)
    }

    var coverImage: StagedImage? {
        sampledImages.first
    }
}

/// A staged text observation context.
struct StagedObservationContext {
    let id: UUID
    var context: ObservationContext
    var addedAt: Date = Date()
    /// Ephemeral refinement-session ownership; never serialized into the request or queue.
    var isRefinementSupplement: Bool = false

    init(context: ObservationContext, addedAt: Date = Date(), isRefinementSupplement: Bool = false, id: UUID = UUID()) {
        self.id = id; self.context = context; self.addedAt = addedAt
        self.isRefinementSupplement = isRefinementSupplement
    }
}
