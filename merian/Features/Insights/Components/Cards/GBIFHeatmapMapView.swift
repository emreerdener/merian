import SwiftUI
import MapKit

// MARK: - GBIF Heatmap Map View

/// Renders a world-level GBIF occurrence density heatmap by compositing two images:
///   1. A base map snapshot from MKMapSnapshotter (no interactive zoom constraints)
///   2. The GBIF zoom-0 tile — a single PNG covering the entire world in Web Mercator
/// Both images share the same Web Mercator projection and world extent, so they align.
struct GBIFHeatmapMapView: View {
    let taxonKey: Int?

    @State private var compositeImage: UIImage?

    var body: some View {
        Group {
            if let image = compositeImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .task(id: taxonKey) {
            compositeImage = await buildComposite()
        }
    }

    // MARK: - Private

    private func buildComposite() async -> UIImage? {
        // To physically trick Apple Maps into unconditionally rendering the ENTIRE WORLD,
        // we MUST request a tiny 256x256 subset. If you ask Apple Maps for 1024 pixels, 
        // it inherently locks the map at a zoomed-in integer MapTile tier.
        let snapshotSize = CGSize(width: 256, height: 256)
        
        async let snapshotTask = makeSnapshot(size: snapshotSize)
        async let tileTask = fetchGBIFTile()

        let (snapshot, tile) = await (snapshotTask, tileTask)
        guard let snapshot else { return tile }

        // Find the absolute coordinate mapping inside the compressed 256x256 space.
        let topLeft = CLLocationCoordinate2D(latitude: 85.05112878, longitude: -180)
        let bottomRight = CLLocationCoordinate2D(latitude: -85.05112878, longitude: 180)
        
        let ptTopLeft = snapshot.point(for: topLeft)
        let ptBottomRight = snapshot.point(for: bottomRight)
        
        let rawWorldRect = CGRect(
            x: ptTopLeft.x,
            y: ptTopLeft.y,
            width: ptBottomRight.x - ptTopLeft.x,
            height: ptBottomRight.y - ptTopLeft.y
        )

        // Rather than allowing the 1024 GBIF Hex tile to become blurry by squashing it
        // into the 256x256 base map, we scale the rendering mathematical canvas back up
        // to a 1024x1024 high-res buffer, massively upscaling both the map & rects.
        let scale: CGFloat = 4.0
        let canvasSize = CGSize(width: snapshotSize.width * scale, height: snapshotSize.height * scale)
        let scaledWorldRect = CGRect(
            x: rawWorldRect.minX * scale,
            y: rawWorldRect.minY * scale,
            width: rawWorldRect.width * scale,
            height: rawWorldRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: canvasSize))
            tile?.draw(in: scaledWorldRect)
        }
    }

    private func makeSnapshot(size: CGSize) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 360)
        )
        options.size = size
        
        // Prevent Retina screens (@2x/@3x scale) from tricking the
        // MapKit tile engine into bumping the integer zoom tier inadvertently!
        options.scale = 1
        
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        return try? await MKMapSnapshotter(options: options).start()
    }

    /// Fetches the GBIF density tile at zoom level 0 — one tile covers the entire world.
    private func fetchGBIFTile() async -> UIImage? {
        guard let key = taxonKey,
              let url = URL(string: "https://api.gbif.org/v2/map/occurrence/density/0/0/0@2x.png?taxonKey=\(key)&style=classic.poly&bin=hex")
        else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
