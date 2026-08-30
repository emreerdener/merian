import SwiftUI

/// Shared raster-backed spectrogram presentation used by capture and insights.
struct AudioSpectrogramView: View, Equatable {
    let columns: [SpectrogramColumn]
    let layout: AudioSpectrogramDisplayLayout

    static func == (
        lhs: AudioSpectrogramView,
        rhs: AudioSpectrogramView
    ) -> Bool {
        lhs.columns.count == rhs.columns.count
            && lhs.columns.last == rhs.columns.last
            && lhs.layout == rhs.layout
    }

    var body: some View {
        ZStack {
            Color(
                red: Double(AudioSpectrogramPalette.backgroundRGBA.red) / 255,
                green: Double(AudioSpectrogramPalette.backgroundRGBA.green) / 255,
                blue: Double(AudioSpectrogramPalette.backgroundRGBA.blue) / 255
            )
            if let image = AudioSpectrogramRenderer.cgImage(
                columns: columns,
                layout: layout
            ) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
        }
    }
}
