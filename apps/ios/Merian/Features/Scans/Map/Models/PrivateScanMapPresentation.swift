import Foundation

struct PrivateScanMapCategoryCount: Identifiable, Equatable, Sendable {
    let category: SearchCategoryBucket
    let count: Int

    var id: String { category.rawValue }
}

struct PrivateScanMapMediaCount: Identifiable, Equatable, Sendable {
    let mediaFilter: ScanMediaFilter
    let count: Int

    var id: String { mediaFilter.rawValue }
}

enum PrivateScanMapPresentation {
    static func discoveriesInViewLabel(count: Int) -> String {
        let noun = count == 1 ? "discovery" : "discoveries"
        return "\(count.formatted()) \(noun) in view"
    }

    static func scanCountLabel(_ count: Int) -> String {
        let noun = count == 1 ? "scan" : "scans"
        return "\(count.formatted()) \(noun)"
    }
}

extension PrivateScanMapPoint {
    var privateMapDisplayName: String {
        let trimmed = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? scientificName : trimmed
    }

    var privateMapMetadata: String {
        let date = timestamp.formatted(date: .abbreviated, time: .omitted)
        guard let locationName,
              !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return date
        }
        return "\(locationName) · \(date)"
    }
}

extension SearchCategoryBucket {
    var privateMapSymbolName: String {
        switch self {
        case .plants: return "leaf"
        case .fungi: return "circle.hexagongrid"
        case .insects: return "ant"
        case .birds: return "bird"
        case .mammals: return "pawprint"
        case .reptiles: return "lizard"
        case .other: return "sparkles"
        }
    }
}

extension ScanMediaFilter {
    var privateMapSymbolName: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        }
    }
}
