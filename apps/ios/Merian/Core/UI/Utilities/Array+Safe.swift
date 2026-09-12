public extension Array {
    /// Safely accesses an element at the specified index.
    /// Returns `nil` when the index is outside the collection's bounds.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
