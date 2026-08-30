import Testing

@testable import Merian

@Suite("AudioSpectrogramRenderer")
struct AudioSpectrogramRendererTests {
    @Test("Fit and live layouts retain their raster dimensions")
    func rasterLayoutsUseFitAndLiveDimensions() throws {
        let columns = (0..<3).map { columnIndex in
            SpectrogramColumn(
                magnitudes: (0..<SpectrogramActor.outputBinCount).map { binIndex in
                    Float(columnIndex + binIndex + 1)
                        / Float(SpectrogramActor.outputBinCount + 3)
                },
                rms: 0.1,
                peak: 0.2
            )
        }

        let fitRaster = try #require(
            AudioSpectrogramRenderer.raster(
                columns: columns,
                layout: .fitToData
            )
        )
        #expect(fitRaster.width == columns.count)
        #expect(fitRaster.height == SpectrogramActor.outputBinCount)

        let liveRaster = try #require(
            AudioSpectrogramRenderer.raster(
                columns: columns,
                layout: .liveHorizon(capacity: 10)
            )
        )
        #expect(liveRaster.width == 10)
        #expect(liveRaster.height == SpectrogramActor.outputBinCount)

        let background = AudioSpectrogramPalette.backgroundRGBA
        let hasSignalPixel = stride(
            from: 0,
            to: liveRaster.pixels.count,
            by: 4
        ).contains { offset in
            liveRaster.pixels[offset] != background.red
                || liveRaster.pixels[offset + 1] != background.green
                || liveRaster.pixels[offset + 2] != background.blue
        }
        #expect(hasSignalPixel)

        let image = try #require(
            AudioSpectrogramRenderer.cgImage(
                columns: columns,
                layout: .liveHorizon(capacity: 10)
            )
        )
        #expect(image.width == 10)
        #expect(image.height == SpectrogramActor.outputBinCount)
    }
}
