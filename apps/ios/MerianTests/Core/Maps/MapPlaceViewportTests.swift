import MapKit
@testable import Merian
import Testing

@MainActor
@Suite("Place search viewport")
struct MapPlaceViewportTests {
    @Test func singleGeographicResultKeepsItsFullExtent() throws {
        let bounds = region(latitudeDelta: 8, longitudeDelta: 10)
        let result = try #require(MapPlaceViewport.results(items: [item()], boundingRegion: bounds).first)
        let viewport = try #require(result.region)
        #expect(viewport.center.latitude == bounds.center.latitude)
        #expect(viewport.center.longitude == bounds.center.longitude)
        #expect(abs(viewport.span.latitudeDelta - 8.8) < 0.0001)
        #expect(abs(viewport.span.longitudeDelta - 11) < 0.0001)
    }

    @Test func multipleMatchesDoNotShareTheAggregateSearchBounds() {
        let items = [item(), item()]
        let results = MapPlaceViewport.results(items: items, boundingRegion: region(latitudeDelta: 80, longitudeDelta: 120))
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.region == nil })
    }

    @Test func pointResultRetainsLocalScale() throws {
        let result = MapPlaceResult(
            label: label, item: item(), region: region(latitudeDelta: 0.002, longitudeDelta: 0.003)
        )
        let viewport = try #require(result.region)
        #expect(viewport.span.latitudeDelta < 0.003)
        #expect(viewport.span.longitudeDelta < 0.004)
    }

    @Test func invalidOrUnrelatedBoundsFallBackToMapItem() {
        let invalid = [
            region(latitudeDelta: 0, longitudeDelta: 0),
            region(latitudeDelta: .nan, longitudeDelta: 10),
            region(latitudeDelta: 10, longitudeDelta: .infinity),
            region(latitudeDelta: 181, longitudeDelta: 10),
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 20),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        ]
        for bounds in invalid {
            #expect(MapPlaceResult(label: label, item: item(), region: bounds).region == nil)
        }
    }

    @Test func dateLineBoundsRemainUsableAndPaddingStaysBounded() throws {
        let acrossDateLine = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 1, longitude: -179)
        ))
        let bounds = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 179),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 8)
        )
        let result = MapPlaceResult(label: label, item: acrossDateLine, region: bounds)
        #expect(try #require(result.region).span.longitudeDelta < 10)
        let world = MapPlaceResult(label: label, item: item(), region: region(latitudeDelta: 180, longitudeDelta: 360))
        #expect(world.region?.span.latitudeDelta == 180)
        #expect(world.region?.span.longitudeDelta == 360)
    }

    private var label: RecentPlace { RecentPlace(title: "Synthetic region", subtitle: "Test area") }

    private func region(latitudeDelta: Double, longitudeDelta: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private func item() -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1)))
    }
}
