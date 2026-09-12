enum InferenceLookalikeCachePolicy {
    /// Versioned kill switch for flushing locally persisted similar-species
    /// blobs after backend validation bugs. Increment only when old
    /// `lookalikesData` / `similarSpecies` must be discarded and rehydrated.
    static let resetVersion = 1
}
