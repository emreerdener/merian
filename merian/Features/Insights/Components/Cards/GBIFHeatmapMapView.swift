import SwiftUI
import MapKit

// MARK: - GBIF Heatmap Map View

/// Renders a live GBIF occurrence density heatmap tile overlay for a given taxon key.
/// Tiles are served from the GBIF Maps API (v2) as hex-binned classic poly overlays.
/// The map is always shown at world zoom so the full distribution is visible.
struct GBIFHeatmapMapView: UIViewRepresentable {
    let taxonKey: Int?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isUserInteractionEnabled = false
        mapView.mapType = .standard
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setVisibleMapRect(MKMapRect.world, animated: false)

        if let key = taxonKey {
            let urlTemplate = "https://api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@2x.png?taxonKey=\(key)&style=classic.poly&bin=hex"
            let overlay = MKTileOverlay(urlTemplate: urlTemplate)
            overlay.canReplaceMapContent = false
            overlay.tileSize = CGSize(width: 512, height: 512)
            mapView.addOverlay(overlay, level: .aboveRoads)
            mapView.delegate = context.coordinator
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }
    }
}
