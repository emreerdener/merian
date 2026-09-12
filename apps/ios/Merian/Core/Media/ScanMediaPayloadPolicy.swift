enum ScanMediaPayloadPolicy {
    /// Maximum compressed image bytes admitted to shared R2 staging.
    static let maxStagedImageBytes = 5 * 1_024 * 1_024

    /// Maximum audio bytes accepted by inference and publication restoration.
    static let maxInferenceAudioBytes = 2_700_000

    /// Hard maximum compressed bytes for a saved Pro micro-clip.
    static let maxSavedVideoBytes = 12 * 1_024 * 1_024

    /// Target longest edge for saved Pro micro-clip playback video.
    static let videoPlaybackLongEdgeMaxPixels = 1_280

    /// Expected compressed storage target below the hard video ceiling.
    static let videoPlaybackExpectedMaxBytes = 3 * 1_024 * 1_024
}
