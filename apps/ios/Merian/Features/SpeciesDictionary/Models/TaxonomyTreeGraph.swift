import Foundation

enum TaxonomyTreeRank: Int, CaseIterable, Hashable {
    case kingdom
    case phylum
    case className
    case order
    case family
    case genus
    case species

    var title: String {
        switch self {
        case .kingdom: "Kingdom"
        case .phylum: "Phylum"
        case .className: "Class"
        case .order: "Order"
        case .family: "Family"
        case .genus: "Genus"
        case .species: "Species"
        }
    }
}

struct TaxonomyTreeNode: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let rank: TaxonomyTreeRank
    let species: SpeciesDictionaryCatalogItem?

    var dictionaryRoute: SpeciesDictionaryRoute? {
        species?.dictionaryRoute
    }
}

struct TaxonomyTreeEdge: Identifiable, Hashable {
    let from: String
    let to: String

    var id: String { "\(from)->\(to)" }
}

struct TaxonomyTreeGraph: Equatable {
    let nodes: [TaxonomyTreeNode]
    let edges: [TaxonomyTreeEdge]

    static let empty = TaxonomyTreeGraph(nodes: [], edges: [])
}

enum TaxonomyTreeGraphBuilder {
    static func build(from items: [SpeciesDictionaryCatalogItem]) -> TaxonomyTreeGraph {
        var nodesByID: [String: TaxonomyTreeNode] = [:]
        var edges = Set<TaxonomyTreeEdge>()

        for item in items.sorted(by: catalogSort) {
            let lineage = [
                (TaxonomyTreeRank.kingdom, item.taxonomy?.kingdom),
                (.phylum, item.taxonomy?.phylum),
                (.className, item.taxonomy?.className),
                (.order, item.taxonomy?.order),
                (.family, item.taxonomy?.family),
                (.genus, item.taxonomy?.genus)
            ]

            var previousNodeID: String?
            var pathParts: [String] = []

            for (rank, rawValue) in lineage {
                let value = normalizedDisplayValue(rawValue)
                pathParts.append(normalizedKey(value))
                let nodeID = "\(rank.rawValue)|\(pathParts.joined(separator: "/"))"
                if nodesByID[nodeID] == nil {
                    nodesByID[nodeID] = TaxonomyTreeNode(
                        id: nodeID,
                        title: value,
                        subtitle: rank.title,
                        rank: rank,
                        species: nil
                    )
                }
                if let previousNodeID {
                    edges.insert(TaxonomyTreeEdge(from: previousNodeID, to: nodeID))
                }
                previousNodeID = nodeID
            }

            let speciesID = "species|\(item.id)"
            nodesByID[speciesID] = TaxonomyTreeNode(
                id: speciesID,
                title: item.commonName,
                subtitle: item.scientificName,
                rank: .species,
                species: item
            )
            if let previousNodeID {
                edges.insert(TaxonomyTreeEdge(from: previousNodeID, to: speciesID))
            }
        }

        return TaxonomyTreeGraph(
            nodes: nodesByID.values.sorted(by: nodeSort),
            edges: edges.sorted { lhs, rhs in lhs.id < rhs.id }
        )
    }

    private static func catalogSort(_ lhs: SpeciesDictionaryCatalogItem, _ rhs: SpeciesDictionaryCatalogItem) -> Bool {
        if lhs.scientificName.localizedCaseInsensitiveCompare(rhs.scientificName) == .orderedSame {
            return lhs.id < rhs.id
        }
        return lhs.scientificName.localizedCaseInsensitiveCompare(rhs.scientificName) == .orderedAscending
    }

    private static func nodeSort(_ lhs: TaxonomyTreeNode, _ rhs: TaxonomyTreeNode) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank.rawValue < rhs.rank.rawValue }
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
            return lhs.id < rhs.id
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func normalizedDisplayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : "Unclassified"
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
