import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SimilarSpeciesImageFetcher {
    private(set) var images: [UIImage] = []
    private(set) var commonName: String?
    private(set) var isLoading = false

    private let dependencies: SimilarSpeciesImageDependencies
    private var activeLoadId: UUID?

    init(dependencies: SimilarSpeciesImageDependencies = .live) {
        self.dependencies = dependencies
    }

    @discardableResult
    func fetchImage(for scientificName: String) async -> Bool {
        guard !scientificName.isEmpty else {
            activeLoadId = UUID()
            images.removeAll()
            commonName = nil
            isLoading = false
            return false
        }
        guard !Task.isCancelled else { return false }

        let loadId = UUID()
        activeLoadId = loadId
        images.removeAll()
        commonName = nil

        isLoading = true
        defer {
            if activeLoadId == loadId {
                isLoading = false
            }
        }

        let output = await dependencies.loadImages(scientificName)
        guard activeLoadId == loadId, !Task.isCancelled else { return false }

        images = output.images
        if let fallbackName = output.commonName,
           fallbackName.lowercased() != scientificName.lowercased() {
            commonName = fallbackName
        }
        return !images.isEmpty
    }
}
