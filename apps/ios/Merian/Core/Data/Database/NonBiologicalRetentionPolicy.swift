enum NonBiologicalRetentionPolicy {
    /// Local and cloud retention window for non-biological scans.
    static let retentionDays = 30

    /// Maximum expired records purged during one foreground cleanup pass.
    static let purgeBatchSize = 250
}
