import Foundation

extension ExploreIdentification {
    var rankDescription: String? {
        switch labelSource {
        case .verifiedSelection: return "Species selected by observer"
        case .community:
            return rank == .species ? "Community identification" : "Community identification · \(rankLabel)"
        case .aiPrimary:
            switch rank {
            case .genus: return "Genus-level identification"
            case .family: return "Family-level identification"
            case .unresolvedBiological: return "Unidentified organism"
            default: return nil
            }
        }
    }

    var originalDescription: String? {
        guard labelSource != .aiPrimary, let originalRank else { return nil }
        let name = originalCommonName ?? originalScientificName ?? "Unidentified organism"
        return "Original AI identification: \(name) (\(originalRank.rawValue.replacingOccurrences(of: "_", with: " ")))"
    }

    private var rankLabel: String {
        rank == .unresolvedBiological ? "Unidentified organism" : rank.rawValue.capitalized
    }
}
