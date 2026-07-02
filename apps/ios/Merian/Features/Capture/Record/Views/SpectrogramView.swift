import SwiftUI
import UIKit

enum SpectrogramPalette {
    private struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }

    static let background = Color(red: 0.06, green: 0.06, blue: 0.1)
    static let backgroundUIColor = UIColor(red: 0.06, green: 0.06, blue: 0.1, alpha: 1.0)

    static func color(for value: Float) -> Color {
        let components = rgb(for: value)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func uiColor(for value: Float) -> UIColor {
        let components = rgb(for: value)
        return UIColor(red: components.red, green: components.green, blue: components.blue, alpha: 1.0)
    }

    private static func rgb(for value: Float) -> RGBComponents {
        let v = max(0, min(1, value))

        switch v {
        case ..<0.2:
            let t = Double(v / 0.2)
            return RGBComponents(red: 0, green: 0, blue: t * 0.8)
        case ..<0.5:
            let t = Double((v - 0.2) / 0.3)
            return RGBComponents(red: 0, green: t * 0.9, blue: 0.8)
        case ..<0.75:
            let t = Double((v - 0.5) / 0.25)
            return RGBComponents(red: t * 0.95, green: 0.9, blue: 0.8 * (1 - t))
        default:
            let t = Double((v - 0.75) / 0.25)
            return RGBComponents(red: 0.95 + t * 0.05, green: 0.9 + t * 0.1, blue: t * 0.8)
        }
    }
}

// MARK: - Spectrogram Canvas

/// Canvas-based 2D scrolling spectrogram. Renders a column-per-FFT-window strip from
/// left (oldest) to right (newest), with frequency increasing bottom-to-top.
/// Uses a 5-stop inferno-style colormap: black → blue → cyan → yellow → white.
struct SpectrogramView: View, Equatable {
    let columns: [SpectrogramColumn]
    let columnCap: Int

    static func == (lhs: SpectrogramView, rhs: SpectrogramView) -> Bool {
        // Fast-path equality check. We only append columns, so count is sufficient.
        lhs.columns.count == rhs.columns.count && lhs.columnCap == rhs.columnCap
    }

    var body: some View {
        Canvas { context, size in
            // Dark canvas surface — spectrograms always render on a dark field.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SpectrogramPalette.background))

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
                        with: .color(SpectrogramPalette.color(for: magnitude))
                    )
                }
            }
        }
    }
}
