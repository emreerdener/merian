import UIKit

extension SpeciesDictionaryCatalogViewModel.Dependencies {
    static let live = Self(
        loadPage: { request in
            try await MerianNetworkClient.shared.getSpeciesDictionaryCatalog(
                category: request.category,
                region: request.region,
                group: request.group,
                query: request.query,
                limit: request.limit,
                cursor: request.cursor
            )
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension SpeciesDictionaryOverviewViewModel.Dependencies {
    static let live = Self(
        loadOverview: {
            try await MerianNetworkClient.shared.getSpeciesDictionaryOverview(
                userRegion: $0
            )
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

@MainActor
struct SpeciesCatalogImageDependencies {
    let loadImage: @MainActor (
        _ source: String,
        _ maxDimension: Int
    ) async -> UIImage?

    static var live: Self {
        Self { source, maxDimension in
            await LocalImageLoader.shared.loadImage(
                fromPath: source,
                maxDimension: maxDimension
            )
        }
    }
}
