import Foundation

public extension Array {
    /// Safely accesses an element at the specified index.
    /// Returns `nil` if the index is out of bounds, preventing fatal runtime index crashes.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Hashable {
    /// Returns the array with duplicate elements removed, preserving original order.
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
