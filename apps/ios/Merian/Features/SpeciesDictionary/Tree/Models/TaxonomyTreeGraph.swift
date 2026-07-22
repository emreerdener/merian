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

    func descendantIDs(of nodeID: String, maximumDepth: Int) -> Set<String> {
        guard maximumDepth > 0 else { return [] }
        var result = Set<String>()
        var queue = (childrenByParentID[nodeID] ?? []).map { (id: $0, depth: 1) }
        var queueIndex = 0

        while queueIndex < queue.count {
            let item = queue[queueIndex]
            queueIndex += 1
            guard item.depth <= maximumDepth, result.insert(item.id).inserted else { continue }
            guard item.depth < maximumDepth else { continue }
            queue.append(contentsOf: (childrenByParentID[item.id] ?? []).map {
                (id: $0, depth: item.depth + 1)
            })
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

        let anchorID = focusedNodeID ?? selectedNodeID
        let overviewRankIndex: Int
        if scale < 1 {
            overviewRankIndex = TaxonomyTreeRank.kingdom.sortIndex
        } else if scale < 1.6 {
            overviewRankIndex = TaxonomyTreeRank.phylum.sortIndex
        } else if scale < 2.4 {
            overviewRankIndex = TaxonomyTreeRank.className.sortIndex
        } else if scale < 2.8 {
            overviewRankIndex = TaxonomyTreeRank.order.sortIndex
        } else if scale < 3.2 {
            overviewRankIndex = TaxonomyTreeRank.family.sortIndex
        } else if scale < 3.6 {
            overviewRankIndex = TaxonomyTreeRank.genus.sortIndex
        } else {
            overviewRankIndex = TaxonomyTreeRank.species.sortIndex
        }
        var visibleIDs = focusedNodeID == nil
            ? Set(nodes.filter { $0.rank.sortIndex <= overviewRankIndex }.map(\.id))
            : []

        guard let anchorID, node(id: anchorID) != nil else {
            return visibleIDs
        }

        visibleIDs.insert(anchorID)
        visibleIDs.formUnion(ancestorIDs(of: anchorID))

        if focusedNodeID == nil {
            visibleIDs.formUnion(contextualSiblingIDs(for: anchorID))
        }

        visibleIDs.formUnion(
            descendantIDs(
                of: anchorID,
                maximumDepth: descendantExpansionDepth(for: scale)
            )
        )

        return visibleIDs
    }

    private func contextualSiblingIDs(for nodeID: String, limit: Int = 12) -> Set<String> {
        guard let parentID = parentByChildID[nodeID] else { return [] }
        let siblings = childrenByParentID[parentID] ?? []
        guard siblings.count > limit, let selectedIndex = siblings.firstIndex(of: nodeID) else {
            return Set(siblings)
        }

        let halfWindow = limit / 2
        let lowerBound = min(max(0, selectedIndex - halfWindow), siblings.count - limit)
        return Set(siblings[lowerBound..<(lowerBound + limit)])
    }

    private func descendantExpansionDepth(for scale: CGFloat) -> Int {
        if scale < 1.6 { return 1 }
        if scale < 2.4 { return 2 }
        if scale < 3.2 { return 3 }
        if scale < 3.6 { return 4 }
        if scale < 3.9 { return 5 }
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
        let semanticScale = stableLayoutScale
        let rankSpacing: CGFloat = 158 / semanticScale
        let descendantAngleSpan = roots.count == 1 ? CGFloat.pi : 2 * CGFloat.pi
        let clusterRadius = roots
            .map { rootID in
                radialGeometry(
                    rootID: rootID,
                    graph: graph,
                    visibleNodeIDs: visibleNodeIDs,
                    rankSpacing: rankSpacing,
                    angleSpan: descendantAngleSpan
                ).maximumRadius
            }
            .max() ?? 0
        let rootOrbitRadius: CGFloat
        if roots.count <= 1 {
            rootOrbitRadius = 0
        } else {
            let minimumClusterChord = max(
                280 / semanticScale,
                clusterRadius * 2 + 150 / semanticScale
            )
            rootOrbitRadius = max(
                360 / semanticScale,
                minimumClusterChord / (2 * sin(CGFloat.pi / CGFloat(roots.count)))
            )
        }
        let padding: CGFloat = 180 / semanticScale
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
                angleStart: roots.count == 1 ? 0 : -CGFloat.pi / 2,
                angleSpan: descendantAngleSpan
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
        guard graph.node(id: focusedNodeID) != nil else {
            return overviewLayout(
                graph: graph,
                visibleNodeIDs: visibleNodeIDs,
                minimumSize: minimumSize
            )
        }

        let semanticScale = stableLayoutScale
        let rankSpacing: CGFloat = 168 / semanticScale
        let descendantAngleSpan = CGFloat.pi
        let descendantRadius = max(
            240 / semanticScale,
            radialGeometry(
                rootID: focusedNodeID,
                graph: graph,
                visibleNodeIDs: visibleNodeIDs,
                rankSpacing: rankSpacing,
                angleSpan: descendantAngleSpan
            ).maximumRadius
        )
        let ancestorCount = graph.ancestorIDs(of: focusedNodeID).count
        let ancestorRadius = (CGFloat(ancestorCount) * 88 + 130) / semanticScale
        let requiredDimension = max(descendantRadius, ancestorRadius) * 2 + 320 / semanticScale
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
            angleStart: 0,
            angleSpan: descendantAngleSpan
        )

        var ancestorID = graph.parentByChildID[focusedNodeID]
        var ancestorIndex = 0
        while let currentAncestorID = ancestorID,
              visibleNodeIDs.contains(currentAncestorID) {
            let radius = (136 + CGFloat(ancestorIndex) * 88) / semanticScale
            let angle = -CGFloat.pi / 2
            positions[currentAncestorID] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            ancestorID = graph.parentByChildID[currentAncestorID]
            ancestorIndex += 1
        }

        placeUnpositionedNodes(
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            positions: &positions,
            center: center,
            radius: max(descendantRadius, ancestorRadius) + 70 / semanticScale
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
        guard graph.node(id: rootID) != nil else { return }
        let geometry = radialGeometry(
            rootID: rootID,
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            rankSpacing: rankSpacing,
            angleSpan: angleSpan
        )
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
            guard let leafIndex = leafIndices[nodeID],
                  let depth = geometry.depthByNodeID[nodeID],
                  let radius = geometry.radiusByDepth[depth] else { continue }
            let angleFraction = leafCount <= 1 ? 0.5 : (leafIndex + 0.5) / leafCount
            let angle = angleStart + angleFraction * angleSpan
            positions[nodeID] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private struct RadialGeometry {
        let depthByNodeID: [String: Int]
        let radiusByDepth: [Int: CGFloat]

        var maximumRadius: CGFloat {
            radiusByDepth.values.max() ?? 0
        }
    }

    /// Geometry is calculated for the closest semantic level and remains fixed.
    /// The view transform supplies the live zoom, so crossing a visibility threshold
    /// cannot move the graph out from under the user's fingers.
    private static let stableLayoutScale: CGFloat = 4

    private static func radialGeometry(
        rootID: String,
        graph: TaxonomyTreeGraph,
        visibleNodeIDs: Set<String>,
        rankSpacing: CGFloat,
        angleSpan: CGFloat
    ) -> RadialGeometry {
        var depthByNodeID: [String: Int] = [rootID: 0]
        var queue: [(id: String, depth: Int)] = [(rootID, 0)]
        var queueIndex = 0

        while queueIndex < queue.count {
            let item = queue[queueIndex]
            queueIndex += 1
            for childID in graph.childrenByParentID[item.id] ?? [] where visibleNodeIDs.contains(childID) {
                guard depthByNodeID[childID] == nil else { continue }
                let childDepth = item.depth + 1
                depthByNodeID[childID] = childDepth
                queue.append((childID, childDepth))
            }
        }

        let nodeCountByDepth = Dictionary(grouping: depthByNodeID.values.filter { $0 > 0 }, by: { $0 })
            .mapValues(\.count)
        var radiusByDepth: [Int: CGFloat] = [:]
        var previousRadius: CGFloat = 0
        let safeAngleSpan = max(angleSpan, CGFloat.pi / 3)
        let minimumArcSpacing = rankSpacing

        for depth in nodeCountByDepth.keys.sorted() {
            let nodeCount = CGFloat(nodeCountByDepth[depth] ?? 1)
            let arcRequiredRadius = nodeCount * minimumArcSpacing / safeAngleSpan
            let radius = max(
                CGFloat(depth) * rankSpacing,
                arcRequiredRadius,
                previousRadius + rankSpacing
            )
            radiusByDepth[depth] = radius
            previousRadius = radius
        }

        return RadialGeometry(
            depthByNodeID: depthByNodeID,
            radiusByDepth: radiusByDepth
        )
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
