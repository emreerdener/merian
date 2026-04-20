import SwiftUI

// MARK: - Spectrogram Canvas

/// Canvas-based 2D scrolling spectrogram. Renders a column-per-FFT-window strip from
/// left (oldest) to right (newest), with frequency increasing bottom-to-top.
/// Uses a 5-stop inferno-style colormap: black → blue → cyan → yellow → white.
struct SpectrogramView: View {
    let columns: [SpectrogramColumn]
    let columnCap: Int

    var body: some View {
        Canvas { context, size in
            // Dark canvas surface — spectrograms always render on a dark field.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.06, green: 0.06, blue: 0.1)))

            guard !columns.isEmpty else { return }
            let colWidth  = size.width  / CGFloat(columns.count)
            let binHeight = size.height / CGFloat(SpectrogramActor.outputBinCount)

            for (ci, column) in columns.enumerated() {
                let x = CGFloat(ci) * colWidth
                for (bi, magnitude) in column.magnitudes.enumerated() {
                    // bi 0 = lowest frequency → bottom of canvas (highest y)
                    let y = size.height - CGFloat(bi + 1) * binHeight
                    context.fill(
                        Path(CGRect(x: x, y: y, width: colWidth + 0.5, height: binHeight + 0.5)),
                        with: .color(color(for: magnitude))
                    )
                }
            }
        }
    }

    // MARK: - Colormap

    private func color(for v: Float) -> Color {
        switch v {
        case ..<0.2:
            let t = Double(v / 0.2)
            return Color(red: 0, green: 0, blue: t * 0.8)
        case ..<0.5:
            let t = Double((v - 0.2) / 0.3)
            return Color(red: 0, green: t * 0.9, blue: 0.8)
        case ..<0.75:
            let t = Double((v - 0.5) / 0.25)
            return Color(red: t * 0.95, green: 0.9, blue: 0.8 * (1 - t))
        default:
            let t = Double((v - 0.75) / 0.25)
            return Color(red: 0.95 + t * 0.05, green: 0.9 + t * 0.1, blue: t * 0.8)
        }
    }
}
