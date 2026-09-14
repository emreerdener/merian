enum ScanningPhrasePolicy {
    /// Existing cloud-analysis deck shared by queued, audio-only, and Describe
    /// presentations. Foreground visual analysis uses its focused morphology
    /// deck in `ScanningPhraseCoordinator`.
    static let cloudAnalysisPhrases = [
        "Scanning subject...",
        "Analyzing subject morphology",
        "Analyzing biological traits",
        "Analyzing structural patterns",
        "Checking taxonomic data",
        "Checking species records",
        "Checking habitat context",
        "Identifying species..."
    ]

    /// Minimum Vision confidence required for a subject-specific phrase deck.
    static let visionConfidenceThreshold: Float = 0.65

    /// Minimum lead the top Vision observation must have over the runner-up.
    static let visionMarginThreshold: Float = 0.15

    /// Pause between consecutive phrases during an active visual scan.
    static let rotationIntervalNanoseconds: UInt64 = 2_300_000_000
}
