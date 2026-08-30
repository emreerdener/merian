import Foundation
import UIKit

enum AudioSpectrogramPalette {
    struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }

    struct RGBAComponents: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    static let backgroundRGBA = RGBAComponents(
        red: 5,
        green: 7,
        blue: 13,
        alpha: 255
    )
    static let backgroundUIColor = UIColor(
        red: CGFloat(backgroundRGBA.red) / 255,
        green: CGFloat(backgroundRGBA.green) / 255,
        blue: CGFloat(backgroundRGBA.blue) / 255,
        alpha: 1
    )

    static func rgba(for value: Float) -> RGBAComponents {
        let components = rgb(for: value)
        return RGBAComponents(
            red: byte(components.red),
            green: byte(components.green),
            blue: byte(components.blue),
            alpha: 255
        )
    }

    private static func rgb(for value: Float) -> RGBComponents {
        let normalizedValue = powf(max(0, min(1, value)), 0.85)
        let stops: [(value: Float, color: RGBComponents)] = [
            (0.00, RGBComponents(red: 0.02, green: 0.027, blue: 0.051)),
            (0.18, RGBComponents(red: 0.02, green: 0.075, blue: 0.27)),
            (0.38, RGBComponents(red: 0.045, green: 0.30, blue: 0.66)),
            (0.58, RGBComponents(red: 0.02, green: 0.70, blue: 0.78)),
            (0.78, RGBComponents(red: 0.48, green: 0.88, blue: 0.43)),
            (0.93, RGBComponents(red: 0.98, green: 0.82, blue: 0.24)),
            (1.00, RGBComponents(red: 1.00, green: 0.98, blue: 0.82))
        ]

        guard let upperIndex = stops.firstIndex(
            where: { normalizedValue <= $0.value }
        ) else {
            return stops[stops.count - 1].color
        }
        guard upperIndex > 0 else { return stops[0].color }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = max(upper.value - lower.value, .ulpOfOne)
        let interpolation = Double(
            (normalizedValue - lower.value) / span
        )

        return RGBComponents(
            red: lower.color.red
                + (upper.color.red - lower.color.red) * interpolation,
            green: lower.color.green
                + (upper.color.green - lower.color.green) * interpolation,
            blue: lower.color.blue
                + (upper.color.blue - lower.color.blue) * interpolation
        )
    }

    private static func byte(_ component: Double) -> UInt8 {
        UInt8(max(0, min(255, Int((component * 255).rounded()))))
    }
}

enum AudioSpectrogramDisplayLayout: Equatable {
    case liveHorizon(capacity: Int)
    case fitToData
}

struct AudioSpectrogramRaster {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

enum AudioSpectrogramRenderer {
    static func raster(
        columns: [SpectrogramColumn],
        layout: AudioSpectrogramDisplayLayout
    ) -> AudioSpectrogramRaster? {
        let visibleColumns = visibleColumns(from: columns, layout: layout)
        let width = rasterWidth(
            for: visibleColumns.count,
            layout: layout
        )
        let height = visibleColumns.map(\.magnitudes.count).max()
            ?? SpectrogramActor.outputBinCount

        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        fill(&pixels, with: AudioSpectrogramPalette.backgroundRGBA)

        for (columnIndex, column) in visibleColumns.enumerated() {
            guard columnIndex < width else { break }
            for (binIndex, magnitude) in column.magnitudes.enumerated()
                where binIndex < height {
                let y = height - binIndex - 1
                let offset = ((y * width) + columnIndex) * 4
                let color = AudioSpectrogramPalette.rgba(for: magnitude)
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }

        return AudioSpectrogramRaster(
            width: width,
            height: height,
            pixels: pixels
        )
    }

    static func cgImage(
        columns: [SpectrogramColumn],
        layout: AudioSpectrogramDisplayLayout
    ) -> CGImage? {
        guard let raster = raster(columns: columns, layout: layout) else {
            return nil
        }

        let data = Data(raster.pixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )

        return CGImage(
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: raster.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func image(
        columns: [SpectrogramColumn],
        layout: AudioSpectrogramDisplayLayout,
        targetSize: CGSize,
        scale: CGFloat = 1
    ) -> UIImage? {
        guard let cgImage = cgImage(columns: columns, layout: layout) else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = scale

        return UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        ).image { rendererContext in
            let context = rendererContext.cgContext
            context.interpolationQuality = .high
            context.setFillColor(
                AudioSpectrogramPalette.backgroundUIColor.cgColor
            )
            context.fill(CGRect(origin: .zero, size: targetSize))
            UIImage(cgImage: cgImage).draw(
                in: CGRect(origin: .zero, size: targetSize)
            )
        }
    }

    private static func visibleColumns(
        from columns: [SpectrogramColumn],
        layout: AudioSpectrogramDisplayLayout
    ) -> [SpectrogramColumn] {
        switch layout {
        case .fitToData:
            return columns
        case .liveHorizon(let capacity):
            guard capacity > 0, columns.count > capacity else {
                return columns
            }
            return Array(columns.suffix(capacity))
        }
    }

    private static func rasterWidth(
        for visibleColumnCount: Int,
        layout: AudioSpectrogramDisplayLayout
    ) -> Int {
        switch layout {
        case .fitToData:
            return visibleColumnCount
        case .liveHorizon(let capacity):
            return max(capacity, visibleColumnCount)
        }
    }

    private static func fill(
        _ pixels: inout [UInt8],
        with color: AudioSpectrogramPalette.RGBAComponents
    ) {
        guard !pixels.isEmpty else { return }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = color.red
            pixels[index + 1] = color.green
            pixels[index + 2] = color.blue
            pixels[index + 3] = color.alpha
        }
    }
}
