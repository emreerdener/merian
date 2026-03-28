import SwiftUI

// MARK: - GBIF Heatmap Map View

/// Renders a world-level GBIF occurrence density heatmap by compositing a static base map
/// entirely removing MapKit CPU overhead, and overlaying the fetched GBIF Zoom-0 tile.
/// Both images share the exact same Web Mercator projection and world extent.
struct GBIFHeatmapMapView: View {
    let taxonKey: Int?

    @State private var tileImage: UIImage?

    var body: some View {
        ZStack {
            // Our flawlessly generated, custom Mapbox topography background!
            Image("WorldMapBase")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if let image = tileImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Dimmed placeholder effect while network loads the tile
                Color(.secondarySystemBackground)
                    .opacity(0.5)
            }
        }
        .task(id: taxonKey) {
            tileImage = await fetchGBIFTile()
        }
    }

    // MARK: - Private

    /// Fetches the GBIF density tile at zoom level 0 — one tile covers the entire world!
    private func fetchGBIFTile() async -> UIImage? {
        guard let key = taxonKey,
              let url = URL(string: "https://api.gbif.org/v2/map/occurrence/density/0/0/0@2x.png?taxonKey=\(key)&style=classic.poly&bin=hex&hexPerTile=120")
        else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}
