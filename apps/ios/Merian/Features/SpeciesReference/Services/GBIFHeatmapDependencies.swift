import Foundation

enum GBIFHeatmapLoadResult: Sendable {
    case image(SendableCGImage)
    case noData
    case serviceUnavailable
    case failed
}

struct GBIFHeatmapDependencies {
    let loadTile: @MainActor (
        _ taxonKey: Int
    ) async -> GBIFHeatmapLoadResult

    init(
        loadTile: @escaping @MainActor (
            _ taxonKey: Int
        ) async -> GBIFHeatmapLoadResult
    ) {
        self.loadTile = loadTile
    }

    static let live = Self { taxonKey in
        await GBIFHeatmapTileService.loadTile(taxonKey: taxonKey)
    }
}

enum GBIFHeatmapTileService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func tileURL(taxonKey: Int) -> URL? {
        URL(string: "https://api.gbif.org/v2/map/occurrence/density/0/0/0@2x.png?taxonKey=\(taxonKey)&style=classic.poly&bin=hex&hexPerTile=135")
    }

    static func loadTile(taxonKey: Int) async -> GBIFHeatmapLoadResult {
        guard let url = tileURL(taxonKey: taxonKey) else { return .failed }

        do {
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse else {
                return .failed
            }

            let disposition = GBIFHeatmapResponsePolicy.disposition(
                statusCode: response.statusCode,
                mimeType: response.mimeType,
                isBodyEmpty: data.isEmpty
            )
            switch disposition {
            case .noData:
                return .noData
            case .serviceUnavailable:
                return .serviceUnavailable
            case .failed:
                return .failed
            case .image:
                break
            }

            let image = autoreleasepool { () -> SendableCGImage? in
                guard let cgImage = ImageDownsampler.downsample(
                    data: data,
                    maxSize: 2_048,
                    stripAlpha: false
                ) else {
                    return nil
                }
                return SendableCGImage(image: cgImage)
            }
            guard let image else { return .failed }
            return .image(image)
        } catch {
            return .failed
        }
    }
}
