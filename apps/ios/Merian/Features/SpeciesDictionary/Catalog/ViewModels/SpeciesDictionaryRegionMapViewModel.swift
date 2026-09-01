import Observation
import UIKit

@MainActor
@Observable
final class SpeciesDictionaryRegionMapViewModel {
    struct Dependencies {
        let loadSnapshot: @MainActor (
            _ query: String,
            _ width: CGFloat,
            _ height: CGFloat,
            _ isDark: Bool
        ) async -> UIImage?
    }

    private(set) var image: UIImage?
    private(set) var isLoading = false

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var requestGeneration = 0

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func load(
        query: String,
        width: CGFloat,
        height: CGFloat,
        isDark: Bool
    ) async {
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        defer {
            if requestGeneration == generation {
                isLoading = false
            }
        }

        let loadedImage = await dependencies.loadSnapshot(
            query,
            width,
            height,
            isDark
        )
        guard !Task.isCancelled,
              requestGeneration == generation
        else {
            return
        }

        image = loadedImage
    }
}
