import CoreGraphics
import Foundation

typealias TaxonomyTreeRank = SpeciesDictionaryTreeRank

struct TaxonomyTreeNode: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let rank: TaxonomyTreeRank
    let parentID: String?
    let speciesCount: Int
    let childCount: Int
    let lineage: SpeciesDictionaryTaxonomy?
    let representativeSpecies: SpeciesDictionaryTreeSpecies?
    let species: SpeciesDictionaryTreeSpecies?

    var dictionaryRoute: SpeciesDictionaryRoute? {
        species?.dictionaryRoute
    }

    var isSpecies: Bool {
        rank == .species
    }

    var searchableText: String {
        [
            title,
            subtitle,
            lineage?.kingdom,
            lineage?.phylum,
            lineage?.className,
            lineage?.order,
            lineage?.family,
            lineage?.genus,
            species?.groupTags.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()
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
    let nodesByID: [String: TaxonomyTreeNode]
    let childrenByParentID: [String: [String]]
    let parentByChildID: [String: String]

    static let empty = TaxonomyTreeGraph(nodes: [], edges: [])

    init(nodes: [TaxonomyTreeNode], edges: [TaxonomyTreeEdge]) {
        let sortedNodes = nodes.sorted(by: Self.nodeSort)
        let sortedEdges = edges.sorted { $0.id < $1.id }
        let nodeLookup = Dictionary(uniqueKeysWithValues: sortedNodes.map { ($0.id, $0) })
        self.nodes = sortedNodes
        self.edges = sortedEdges
        self.nodesByID = nodeLookup
        self.parentByChildID = Dictionary(uniqueKeysWithValues: sortedEdges.map { ($0.to, $0.from) })
        self.childrenByParentID = Dictionary(grouping: sortedEdges, by: \.from)
            .mapValues { edges in
                edges
                    .map(\.to)
                    .sorted { lhs, rhs in
                        guard let lhsNode = nodeLookup[lhs], let rhsNode = nodeLookup[rhs] else {
                            return lhs < rhs
                        }
                        return Self.nodeSort(lhsNode, rhsNode)
                    }
            }
    }

    var rootNodeIDs: [String] {
        nodes
            .filter { parentByChildID[$0.id] == nil }
            .sorted(by: Self.nodeSort)
            .map(\.id)
    }

    func node(id: String?) -> TaxonomyTreeNode? {
        guard let id else { return nil }
        return nodesByID[id]
    }

    func ancestorIDs(of nodeID: String) -> Set<String> {
        var ids = Set<String>()
        var current = parentByChildID[nodeID]
        while let id = current {
            ids.insert(id)
            current = parentByChildID[id]
        }
        return ids
    }

    func descendantIDs(of nodeID: String) -> Set<String> {
        var result = Set<String>()
        var stack = childrenByParentID[nodeID] ?? []
        while let id = stack.popLast() {
            guard result.insert(id).inserted else { continue }
            stack.append(contentsOf: childrenByParentID[id] ?? [])
        }
        return result
    }

    func connectedIDs(for nodeID: String?) -> Set<String> {
        guard let nodeID else { return [] }
        var ids: Set<String> = [nodeID]
        ids.formUnion(ancestorIDs(of: nodeID))
        ids.formUnion(childrenByParentID[nodeID] ?? [])
        return ids
    }

    func searchResults(for query: String, limit: Int = 8) -> [TaxonomyTreeNode] {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard !normalized.isEmpty else { return [] }

        return nodes
            .filter { $0.searchableText.contains(normalized) }
            .sorted { lhs, rhs in
                if lhs.isSpecies != rhs.isSpecies { return lhs.isSpecies && !rhs.isSpecies }
                if lhs.speciesCount != rhs.speciesCount { return lhs.speciesCount > rhs.speciesCount }
                return Self.nodeSort(lhs, rhs)
            }
            .prefix(limit)
            .map { $0 }
    }

    func visibleNodeIDs(focusedNodeID: String?, selectedNodeID: String?, scale: CGFloat) -> Set<String> {
        guard !nodes.isEmpty else { return [] }
        let selectedLineage = selectedNodeID.map { ancestorIDs(of: $0).union([$0]) } ?? []

        if let focusedNodeID {
            var ids = ancestorIDs(of: focusedNodeID)
            ids.insert(focusedNodeID)
            ids.formUnion(descendantIDs(of: focusedNodeID))

            if let focus = node(id: focusedNodeID),
               focus.rank.sortIndex < TaxonomyTreeRank.family.sortIndex,
               scale < 1.05 {
                ids = ids.filter { id in
                    guard let node = node(id: id) else { return false }
                    return node.rank != .species || selectedLineage.contains(id)
                }
            }

            ids.formUnion(selectedLineage)
            return ids
        }

        let maxRank: TaxonomyTreeRank
        if scale < 0.72 {
            maxRank = .order
        } else if scale < 1.05 {
            maxRank = .genus
        } else {
            maxRank = .species
        }

        var ids = Set(nodes.filter { $0.rank.sortIndex <= maxRank.sortIndex }.map(\.id))
        ids.formUnion(selectedLineage)
        return ids
    }

    private static func nodeSort(_ lhs: TaxonomyTreeNode, _ rhs: TaxonomyTreeNode) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank.sortIndex < rhs.rank.sortIndex }
        if lhs.parentID != rhs.parentID { return (lhs.parentID ?? "") < (rhs.parentID ?? "") }
        if lhs.speciesCount != rhs.speciesCount { return lhs.speciesCount > rhs.speciesCount }
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedSame {
            return lhs.id < rhs.id
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

enum TaxonomyTreeGraphBuilder {
    static func build(from payload: SpeciesDictionaryTreePayload) -> TaxonomyTreeGraph {
        let nodes = payload.nodes.map { node in
            TaxonomyTreeNode(
                id: node.id,
                title: node.title,
                subtitle: node.subtitle,
                rank: node.rank,
                parentID: node.parentId,
                speciesCount: node.speciesCount,
                childCount: node.childCount,
                lineage: node.lineage,
                representativeSpecies: node.representativeSpecies,
                species: node.species
            )
        }
        let edges = payload.edges.map { TaxonomyTreeEdge(from: $0.from, to: $0.to) }
        return TaxonomyTreeGraph(nodes: nodes, edges: edges)
    }
}

struct TaxonomyTreeLayout: Equatable {
    let positions: [String: CGPoint]
    let size: CGSize

    static func make(
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        minimumSize: CGSize
    ) -> TaxonomyTreeLayout {
        guard !visibleNodeIDs.isEmpty else {
            return TaxonomyTreeLayout(positions: [:], size: minimumSize)
        }

        let horizontalSpacing: CGFloat = 230
        let verticalSpacing: CGFloat = 86
        let leftPadding: CGFloat = 120
        let topPadding: CGFloat = 88
        var positions: [String: CGPoint] = [:]
        var nextLeafIndex: CGFloat = 0

        let roots = graph.rootNodeIDs.filter { visibleNodeIDs.contains($0) }
        for rootID in roots {
            assignPosition(
                nodeID: rootID,
                graph: graph,
                visibleNodeIDs: visibleNodeIDs,
                positions: &positions,
                nextLeafIndex: &nextLeafIndex,
                horizontalSpacing: horizontalSpacing,
                verticalSpacing: verticalSpacing,
                leftPadding: leftPadding,
                topPadding: topPadding
            )
            nextLeafIndex += 0.8
        }

        for node in graph.nodes where visibleNodeIDs.contains(node.id) && positions[node.id] == nil {
            positions[node.id] = CGPoint(
                x: leftPadding + CGFloat(node.rank.sortIndex) * horizontalSpacing,
                y: topPadding + nextLeafIndex * verticalSpacing
            )
            nextLeafIndex += 1
        }

        let maxRankIndex = visibleNodeIDs
            .compactMap { graph.node(id: $0)?.rank.sortIndex }
            .max() ?? 0
        let width = max(minimumSize.width, leftPadding * 2 + CGFloat(maxRankIndex) * horizontalSpacing + 220)
        let height = max(minimumSize.height, topPadding * 2 + max(1, nextLeafIndex) * verticalSpacing)

        return TaxonomyTreeLayout(
            positions: positions,
            size: CGSize(width: width, height: height)
        )
    }

    @discardableResult
    private static func assignPosition(
        nodeID: String,
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        positions: inout [String: CGPoint],
        nextLeafIndex: inout CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
        leftPadding: CGFloat,
        topPadding: CGFloat
    ) -> CGFloat {
        guard let node = graph.node(id: nodeID) else {
            return nextLeafIndex
        }

        let visibleChildren = (graph.childrenByParentID[nodeID] ?? [])
            .filter { visibleNodeIDs.contains($0) }
        let yIndex: CGFloat
        if visibleChildren.isEmpty {
            yIndex = nextLeafIndex
            nextLeafIndex += 1
        } else {
            let childYValues = visibleChildren.map { childID in
                assignPosition(
                    nodeID: childID,
                    graph: graph,
                    visibleNodeIDs: visibleNodeIDs,
                    positions: &positions,
                    nextLeafIndex: &nextLeafIndex,
                    horizontalSpacing: horizontalSpacing,
                    verticalSpacing: verticalSpacing,
                    leftPadding: leftPadding,
                    topPadding: topPadding
                )
            }
            yIndex = childYValues.reduce(0, +) / CGFloat(childYValues.count)
        }

        positions[nodeID] = CGPoint(
            x: leftPadding + CGFloat(node.rank.sortIndex) * horizontalSpacing,
            y: topPadding + yIndex * verticalSpacing
        )
        return yIndex
    }
}
