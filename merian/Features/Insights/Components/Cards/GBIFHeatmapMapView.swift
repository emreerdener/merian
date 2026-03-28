import SwiftUI
import MapKit

// MARK: - GBIF Capabilities Response

private struct GBIFCapabilitiesResponse: Decodable {
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double
    let total: Int
}

// MARK: - GBIF Heatmap Map View

/// Renders a live GBIF occurrence density heatmap tile overlay for a given taxon key.
/// Tiles are served from the GBIF Maps API (v2) as hex-binned classic poly overlays.
/// Automatically fetches the taxonomic capabilities bounding box to frame the heatmap.
struct GBIFHeatmapMapView: UIViewRepresentable {
    let taxonKey: Int

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isUserInteractionEnabled = false
        mapView.mapType = .standard
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .excludingAll

        let urlTemplate = "https://api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@2x.png?taxonKey=\(taxonKey)&style=classic.poly&bin=hex"
        let overlay = MKTileOverlay(urlTemplate: urlTemplate)
        overlay.canReplaceMapContent = false
        overlay.tileSize = CGSize(width: 512, height: 512)
        mapView.addOverlay(overlay, level: .aboveRoads)
        mapView.delegate = context.coordinator

        // Start with the full world view.
        mapView.setRegion(Self.worldRegion, animated: false)
        
        // Fetch the bounding box and animate the zoom.
        fetchCapabilitiesAndZoom(for: mapView)

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static let worldRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 360)
    )

    private func fetchCapabilitiesAndZoom(for mapView: MKMapView) {
        let urlString = "https://api.gbif.org/v2/map/occurrence/density/capabilities.json?taxonKey=\(taxonKey)"
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let response = try? JSONDecoder().decode(GBIFCapabilitiesResponse.self, from: data), response.total > 0 {
                    await MainActor.run {
                        let latDelta = abs(response.maxLat - response.minLat)
                        let lngDelta = abs(response.maxLng - response.minLng)

                        // When the distribution spans more than half the globe longitudinally,
                        // the bounding-box midpoint lands in an uninhabited ocean between two
                        // range clusters (e.g. North America + Eurasia → midpoint over Africa).
                        // Show the world view instead of centering on a misleading midpoint.
                        if lngDelta > 180 {
                            mapView.setRegion(Self.worldRegion, animated: true)
                            return
                        }

                        let centerLatRaw = (response.minLat + response.maxLat) / 2
                        let centerLngRaw = (response.minLng + response.maxLng) / 2

                        // Normalize latitude and longitude bounds to prevent MapKit NSInvalidArgumentException
                        let centerLat = min(max(centerLatRaw, -89.9), 89.9)
                        var centerLng = centerLngRaw.truncatingRemainder(dividingBy: 360.0)
                        if centerLng > 180.0 { centerLng -= 360.0 }
                        else if centerLng < -180.0 { centerLng += 360.0 }

                        // Add 60% padding around the edges so the distribution has breathing room from the map border.
                        let spanLat = latDelta * 1.6
                        let spanLng = lngDelta * 1.6

                        // Constrain the span to avoid over-zooming on isolated points and wrap at map edges.
                        // MapKit limits Mercator latitudes to roughly 170 span to avoid infinite distortion.
                        let finalLatDelta = min(max(spanLat, 10.0), 170.0)
                        let finalLngDelta = min(max(spanLng, 10.0), 360.0)

                        let region = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
                            span: MKCoordinateSpan(latitudeDelta: finalLatDelta, longitudeDelta: finalLngDelta)
                        )
                        mapView.setRegion(region, animated: true)
                    }
                }
            } catch {
                print("Failed to fetch GBIF capabilities for taxonKey \(taxonKey): \(error)")
            }
        }
    }
    
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }
    }
}
