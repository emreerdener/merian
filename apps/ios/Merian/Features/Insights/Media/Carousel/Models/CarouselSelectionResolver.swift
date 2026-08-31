import Foundation

protocol CarouselSelectionCandidate {
    var id: String { get }
    var imageIdentifier: String? { get }
    var imageOrigin: CarouselImageOrigin? { get }
}

enum CarouselSelectionResolver {
    static func selectedIndex<Candidate: CarouselSelectionCandidate>(
        preserving selectedPageID: String?,
        previousSelectedIndex: Int,
        in pages: [Candidate],
        loadedReferenceIdentifiers: Set<String>
    ) -> Int {
        guard !pages.isEmpty else { return 0 }

        if let selectedPageID,
           let preservedIndex = pages.firstIndex(where: {
               $0.id == selectedPageID
           }) {
            return preservedIndex
        }

        if let loadedReferenceIndex = pages.firstIndex(where: { page in
            guard page.imageOrigin == .reference,
                  let identifier = page.imageIdentifier else {
                return false
            }
            return loadedReferenceIdentifiers.contains(identifier)
        }) {
            return loadedReferenceIndex
        }

        return max(0, min(previousSelectedIndex, pages.count - 1))
    }
}
