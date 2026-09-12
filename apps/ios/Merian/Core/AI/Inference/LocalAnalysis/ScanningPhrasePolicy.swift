enum ScanningPhrasePolicy {
    /// Minimum Vision confidence required for a subject-specific phrase deck.
    static let visionConfidenceThreshold: Float = 0.65

    /// Minimum lead the top Vision observation must have over the runner-up.
    static let visionMarginThreshold: Float = 0.15

    /// Pause between consecutive phrases during an active visual scan.
    static let rotationIntervalNanoseconds: UInt64 = 2_300_000_000
}
