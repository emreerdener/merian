import Foundation

enum GBIFHeatmapLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case noTaxonKey
    case noData
    case serviceUnavailable
    case failed

    var overlayMessage: String? {
        switch self {
        case .noTaxonKey, .noData:
            return "No distribution data available"
        case .serviceUnavailable:
            return "Habitat data not available"
        case .failed:
            return "Distribution map unavailable"
        case .idle, .loading, .loaded:
            return nil
        }
    }
}

enum GBIFHeatmapResponseDisposition: Equatable, Sendable {
    case image
    case noData
    case serviceUnavailable
    case failed
}

enum GBIFHeatmapResponsePolicy {
    static func disposition(
        statusCode: Int,
        mimeType: String?,
        isBodyEmpty: Bool
    ) -> GBIFHeatmapResponseDisposition {
        switch statusCode {
        case 200:
            break
        case 204, 404:
            return .noData
        case 503:
            return .serviceUnavailable
        case 200..<300 where isBodyEmpty:
            return .noData
        case 200..<300:
            break
        default:
            return .failed
        }

        guard !isBodyEmpty else { return .noData }
        if let mimeType,
           !mimeType.lowercased().hasPrefix("image/") {
            return .failed
        }
        return .image
    }
}
