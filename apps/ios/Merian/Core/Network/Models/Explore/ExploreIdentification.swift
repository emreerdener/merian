import Foundation

/// Server-projected public label semantics, separate from any confidence badge.
struct ExploreIdentification: Decodable, Equatable, Sendable {
    enum Source: String, Decodable, Sendable {
        case aiPrimary = "ai_primary"
        case verifiedSelection = "verified_selection"
        case community
    }
    let version: Int
    let rank: PrimaryIdentification.Resolution
    let labelSource: Source
    let originalRank: PrimaryIdentification.Resolution?
    let originalScientificName: String?
    let originalCommonName: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, rank, labelSource, originalRank, originalScientificName, originalCommonName
    }

    private struct FieldKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: FieldKey.self)
        guard Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw PrimaryIdentification.IntegrityError.invalidSnapshot
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        rank = try values.decode(PrimaryIdentification.Resolution.self, forKey: .rank)
        labelSource = try values.decode(Source.self, forKey: .labelSource)
        originalRank = try values.decode(PrimaryIdentification.Resolution?.self, forKey: .originalRank)
        originalScientificName = try values.decode(String?.self, forKey: .originalScientificName)
        originalCommonName = try values.decode(String?.self, forKey: .originalCommonName)
        guard version == 1, rank != .nonBiological, originalRank != .nonBiological,
              labelSource != .verifiedSelection || rank == .species,
              labelSource == .community || originalRank != nil,
              labelSource != .aiPrimary || rank == originalRank else {
            throw PrimaryIdentification.IntegrityError.invalidSnapshot
        }
        if let originalRank {
            _ = try PrimaryIdentification.Snapshot(resolution: originalRank,
                                                   scientificName: originalScientificName,
                                                   commonName: originalCommonName)
        } else if originalScientificName != nil || originalCommonName != nil {
            throw PrimaryIdentification.IntegrityError.invalidSnapshot
        }
    }

    var permitsSpeciesPresentation: Bool { rank == .species && labelSource != .community }

}
