import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class GBIFHeatmapViewModel {
    private(set) var tileImage: UIImage?
    private(set) var loadState: GBIFHeatmapLoadState = .idle

    private let dependencies: GBIFHeatmapDependencies
    private var activeLoadId: UUID?

    init(dependencies: GBIFHeatmapDependencies = .live) {
        self.dependencies = dependencies
    }

    func load(taxonKey: Int?) async {
        guard let taxonKey else {
            activeLoadId = UUID()
            tileImage = nil
            loadState = .noTaxonKey
            return
        }
        guard !Task.isCancelled else { return }

        let loadId = UUID()
        activeLoadId = loadId
        tileImage = nil

        loadState = .loading
        let result = await dependencies.loadTile(taxonKey)
        guard activeLoadId == loadId, !Task.isCancelled else { return }

        switch result {
        case .image(let image):
            tileImage = UIImage(cgImage: image.image)
            loadState = .loaded
        case .noData:
            loadState = .noData
        case .serviceUnavailable:
            loadState = .serviceUnavailable
        case .failed:
            loadState = .failed
        }
    }
}
