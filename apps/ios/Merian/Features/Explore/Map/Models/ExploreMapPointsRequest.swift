import MapKit

struct ExploreMapPointsRequest {
    let region: MKCoordinateRegion
    let zoomLevel: Double
    let limit: Int
    let speciesCategories: Set<ExploreMapSpeciesCategory>
    let mediaTypes: Set<ExploreMediaKind>
}
