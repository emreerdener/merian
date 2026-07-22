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

        let overviewRankIndex: Int
        if scale < 0.68 {
            overviewRankIndex = TaxonomyTreeRank.kingdom.sortIndex
        } else if scale < 0.82 {
            overviewRankIndex = TaxonomyTreeRank.phylum.sortIndex
        } else {
            overviewRankIndex = TaxonomyTreeRank.className.sortIndex
        }

        let anchorID = focusedNodeID ?? selectedNodeID
        let baselineRankIndex = focusedNodeID == nil
            ? overviewRankIndex
            : TaxonomyTreeRank.kingdom.sortIndex
        var visibleIDs = Set(
            nodes
                .filter { $0.rank.sortIndex <= baselineRankIndex }
                .map(\.id)
        )

        guard let anchorID, let anchorNode = node(id: anchorID) else {
            return visibleIDs
        }

        visibleIDs.insert(anchorID)
        visibleIDs.formUnion(ancestorIDs(of: anchorID))

        if let parentID = parentByChildID[anchorID] {
            visibleIDs.formUnion(childrenByParentID[parentID] ?? [])
        }

        let descendantRankLimit = min(
            TaxonomyTreeRank.species.sortIndex,
            anchorNode.rank.sortIndex + descendantExpansionDepth(for: scale)
        )
        visibleIDs.formUnion(
            descendantIDs(of: anchorID).filter { descendantID in
                guard let descendant = node(id: descendantID) else { return false }
                return descendant.rank.sortIndex <= descendantRankLimit
            }
        )

        return visibleIDs
    }

    private func descendantExpansionDepth(for scale: CGFloat) -> Int {
        if scale < 1.05 { return 1 }
        if scale < 1.35 { return 2 }
        if scale < 1.7 { return 3 }
        if scale < 2 { return 4 }
        return TaxonomyTreeRank.allCases.count
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

struct TaxonomyConstellationLayout: Equatable {
    let positions: [String: CGPoint]
    let size: CGSize

    static func make(
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        focusedNodeID: String?,
        minimumSize: CGSize
    ) -> TaxonomyConstellationLayout {
        guard !visibleNodeIDs.isEmpty else {
            return TaxonomyConstellationLayout(positions: [:], size: minimumSize)
        }

        if let focusedNodeID,
           visibleNodeIDs.contains(focusedNodeID),
           graph.node(id: focusedNodeID) != nil {
            return focusedLayout(
                graph: graph,
                visibleNodeIDs: visibleNodeIDs,
                focusedNodeID: focusedNodeID,
                minimumSize: minimumSize
            )
        }

        return overviewLayout(
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            minimumSize: minimumSize
        )
    }

    private static func overviewLayout(
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        minimumSize: CGSize
    ) -> TaxonomyConstellationLayout {
        let roots = graph.rootNodeIDs.filter { visibleNodeIDs.contains($0) }
        let maximumRelativeDepth = roots.reduce(0) { currentMaximum, rootID in
            guard let root = graph.node(id: rootID) else { return currentMaximum }
            let rootMaximum = graph.descendantIDs(of: rootID)
                .filter { visibleNodeIDs.contains($0) }
                .compactMap { graph.node(id: $0)?.rank.sortIndex }
                .map { max(0, $0 - root.rank.sortIndex) }
                .max() ?? 0
            return max(currentMaximum, rootMaximum)
        }
        let rankSpacing: CGFloat = 88
        let clusterRadius = max(150, CGFloat(maximumRelativeDepth) * rankSpacing + 52)
        let rootOrbitRadius: CGFloat = roots.count <= 1
            ? 0
            : max(270, CGFloat(roots.count) * 42)
        let padding: CGFloat = 120
        let requiredDimension = (rootOrbitRadius + clusterRadius + padding) * 2
        let width = max(minimumSize.width, requiredDimension)
        let height = max(minimumSize.height, requiredDimension)
        let center = CGPoint(x: width / 2, y: height / 2)
        var positions: [String: CGPoint] = [:]

        for (index, rootID) in roots.enumerated() {
            let rootAngle = roots.count <= 1
                ? -CGFloat.pi / 2
                : -CGFloat.pi / 2 + CGFloat(index) * 2 * CGFloat.pi / CGFloat(roots.count)
            let rootCenter = CGPoint(
                x: center.x + cos(rootAngle) * rootOrbitRadius,
                y: center.y + sin(rootAngle) * rootOrbitRadius
            )
            positions[rootID] = rootCenter
            assignRadialDescendants(
                rootID: rootID,
                center: rootCenter,
                graph: graph,
                visibleNodeIDs: visibleNodeIDs,
                positions: &positions,
                rankSpacing: rankSpacing,
                angleStart: -CGFloat.pi / 2,
                angleSpan: 2 * CGFloat.pi
            )
        }

        placeUnpositionedNodes(
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            positions: &positions,
            center: center,
            radius: rootOrbitRadius + clusterRadius
        )

        return TaxonomyConstellationLayout(
            positions: positions,
            size: CGSize(width: width, height: height)
        )
    }

    private static func focusedLayout(
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        focusedNodeID: String,
        minimumSize: CGSize
    ) -> TaxonomyConstellationLayout {
        guard let focusedNode = graph.node(id: focusedNodeID) else {
            return overviewLayout(
                graph: graph,
                visibleNodeIDs: visibleNodeIDs,
                minimumSize: minimumSize
            )
        }

        let maximumRelativeDepth = graph.descendantIDs(of: focusedNodeID)
            .filter { visibleNodeIDs.contains($0) }
            .compactMap { graph.node(id: $0)?.rank.sortIndex }
            .map { max(0, $0 - focusedNode.rank.sortIndex) }
            .max() ?? 0
        let rankSpacing: CGFloat = 108
        let descendantRadius = max(210, CGFloat(maximumRelativeDepth) * rankSpacing + 70)
        let ancestorCount = graph.ancestorIDs(of: focusedNodeID).count
        let ancestorRadius = CGFloat(ancestorCount) * 68 + 100
        let requiredDimension = max(descendantRadius, ancestorRadius) * 2 + 240
        let width = max(minimumSize.width, requiredDimension)
        let height = max(minimumSize.height, requiredDimension)
        let center = CGPoint(x: width / 2, y: height / 2)
        var positions: [String: CGPoint] = [focusedNodeID: center]

        assignRadialDescendants(
            rootID: focusedNodeID,
            center: center,
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            positions: &positions,
            rankSpacing: rankSpacing,
            angleStart: -CGFloat.pi / 3,
            angleSpan: 5 * CGFloat.pi / 3
        )

        var ancestorID = graph.parentByChildID[focusedNodeID]
        var ancestorIndex = 0
        while let currentAncestorID = ancestorID,
              visibleNodeIDs.contains(currentAncestorID) {
            let radius = 118 + CGFloat(ancestorIndex) * 68
            let angle = -CGFloat.pi / 2 - CGFloat(ancestorIndex) * CGFloat.pi / 18
            positions[currentAncestorID] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            ancestorID = graph.parentByChildID[currentAncestorID]
            ancestorIndex += 1
        }

        if let parentID = graph.parentByChildID[focusedNodeID] {
            let siblingIDs = (graph.childrenByParentID[parentID] ?? [])
                .filter { visibleNodeIDs.contains($0) && $0 != focusedNodeID }
            let siblingRadius = max(190, ancestorRadius + 46)
            for (index, siblingID) in siblingIDs.enumerated() {
                let fraction = CGFloat(index + 1) / CGFloat(siblingIDs.count + 1)
                let angle = CGFloat.pi + fraction * CGFloat.pi
                positions[siblingID] = CGPoint(
                    x: center.x + cos(angle) * siblingRadius,
                    y: center.y + sin(angle) * siblingRadius
                )
            }
        }

        placeUnpositionedNodes(
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            positions: &positions,
            center: center,
            radius: max(descendantRadius, ancestorRadius) + 70
        )

        return TaxonomyConstellationLayout(
            positions: positions,
            size: CGSize(width: width, height: height)
        )
    }

    private static func assignRadialDescendants(
        rootID: String,
        center: CGPoint,
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        positions: inout [String: CGPoint],
        rankSpacing: CGFloat,
        angleStart: CGFloat,
        angleSpan: CGFloat
    ) {
        guard let rootNode = graph.node(id: rootID) else { return }
        var leafIndices: [String: CGFloat] = [:]
        var nextLeafIndex: CGFloat = 0
        assignLeafIndex(
            nodeID: rootID,
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            leafIndices: &leafIndices,
            nextLeafIndex: &nextLeafIndex
        )
        let leafCount = max(1, nextLeafIndex)

        for nodeID in leafIndices.keys where nodeID != rootID {
            guard let node = graph.node(id: nodeID), let leafIndex = leafIndices[nodeID] else { continue }
            let relativeDepth = max(1, node.rank.sortIndex - rootNode.rank.sortIndex)
            let angleFraction = leafCount <= 1 ? 0.5 : (leafIndex + 0.5) / leafCount
            let angle = angleStart + angleFraction * angleSpan
            let radius = CGFloat(relativeDepth) * rankSpacing
            positions[nodeID] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    @discardableResult
    private static func assignLeafIndex(
        nodeID: String,
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        leafIndices: inout [String: CGFloat],
        nextLeafIndex: inout CGFloat
    ) -> CGFloat {
        let visibleChildren = (graph.childrenByParentID[nodeID] ?? [])
            .filter { visibleNodeIDs.contains($0) }
        let leafIndex: CGFloat
        if visibleChildren.isEmpty {
            leafIndex = nextLeafIndex
            nextLeafIndex += 1
        } else {
            let childIndices = visibleChildren.map { childID in
                assignLeafIndex(
                    nodeID: childID,
                    graph: graph,
                    visibleNodeIDs: visibleNodeIDs,
                    leafIndices: &leafIndices,
                    nextLeafIndex: &nextLeafIndex
                )
            }
            leafIndex = childIndices.reduce(0, +) / CGFloat(childIndices.count)
        }
        leafIndices[nodeID] = leafIndex
        return leafIndex
    }

    private static func placeUnpositionedNodes(
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        positions: inout [String: CGPoint],
        center: CGPoint,
        radius: CGFloat
    ) {
        let unpositionedIDs = graph.nodes
            .map(\.id)
            .filter { visibleNodeIDs.contains($0) && positions[$0] == nil }
        guard !unpositionedIDs.isEmpty else { return }

        for (index, nodeID) in unpositionedIDs.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * CGFloat.pi / CGFloat(unpositionedIDs.count)
            positions[nodeID] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }
}
