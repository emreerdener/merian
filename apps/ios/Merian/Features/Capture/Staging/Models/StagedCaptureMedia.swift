import Foundation

/// A staged audio recording track with its captured file path.
struct StagedAudio {
    let filePath: String
    var addedAt: Date = Date()
}

/// A staged short video clip with sampled frame images used for AI inference.
struct StagedVideo {
    let filePath: String
    let sampledImages: [StagedImage]
    let audioFilePath: String?
    var addedAt: Date = Date()

    init(
        filePath: String,
        sampledImages: [StagedImage],
        audioFilePath: String? = nil,
        addedAt: Date = Date()
    ) {
        self.filePath = filePath
        self.sampledImages = sampledImages
        self.audioFilePath = audioFilePath
        self.addedAt = addedAt
    }

    var coverImage: StagedImage? {
        sampledImages.first
    }
}

/// A staged text observation context.
struct StagedObservationContext {
    let context: ObservationContext
    var addedAt: Date = Date()
}
