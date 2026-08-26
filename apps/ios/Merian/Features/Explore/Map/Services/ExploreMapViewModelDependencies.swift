import Foundation

extension ExploreMapViewModel.Dependencies {
    static let live = Self(
        loadPoints: { request in
            try await MerianNetworkClient.shared.getExploreMapPoints(
                northLatitude: request.region.exploreMapNorthLatitude,
                southLatitude: request.region.exploreMapSouthLatitude,
                eastLongitude: request.region.exploreMapEastLongitude,
                westLongitude: request.region.exploreMapWestLongitude,
                zoomLevel: request.zoomLevel,
                limit: request.limit,
                speciesCategories: request.speciesCategories,
                mediaTypes: request.mediaTypes
            )
        },
        now: Date.init,
        debounceCameraSearch: {
            try await Task.sleep(for: .seconds(1.5))
        }
    )
}
