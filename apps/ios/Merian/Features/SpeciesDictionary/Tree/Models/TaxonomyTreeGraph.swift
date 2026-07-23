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
    let rootNodeIDs: [String]

    static let empty = TaxonomyTreeGraph(nodes: [], edges: [])

    init(nodes: [TaxonomyTreeNode], edges: [TaxonomyTreeEdge]) {
        let sortedNodes = nodes.sorted(by: Self.nodeSort)
        let sortedEdges = edges.sorted { $0.id < $1.id }
        let nodeLookup = Dictionary(uniqueKeysWithValues: sortedNodes.map { ($0.id, $0) })
        self.nodes = sortedNodes
        self.edges = sortedEdges
        self.nodesByID = nodeLookup
        let parentLookup = Dictionary(uniqueKeysWithValues: sortedEdges.map { ($0.to, $0.from) })
        self.parentByChildID = parentLookup
        self.rootNodeIDs = sortedNodes
            .filter { parentLookup[$0.id] == nil }
            .map(\.id)
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

    func visibleNodeIDs(focusedNodeID: String?, selectedNodeID _: String?, scale _: CGFloat) -> Set<String> {
        guard !nodes.isEmpty else { return [] }

        guard let focusedNodeID, node(id: focusedNodeID) != nil else {
            // The overview is a persistent map too. Wide zoom uses compact marks and
            // fewer labels instead of removing ranks from the constellation.
            return Set(nodes.map(\.id))
        }

        var visibleIDs: Set<String> = [focusedNodeID]
        visibleIDs.formUnion(ancestorIDs(of: focusedNodeID))
        visibleIDs.formUnion(descendantIDs(of: focusedNodeID))
        return visibleIDs
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

struct TaxonomyConstellationEdgeSegment {
    let edge: TaxonomyTreeEdge
    let endNode: TaxonomyTreeNode
    let startPoint: CGPoint
    let endPoint: CGPoint

    fileprivate var bounds: CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        .insetBy(dx: -1, dy: -1)
    }

    fileprivate func intersects(_ rect: CGRect) -> Bool {
        guard bounds.intersects(rect) else { return false }
        if rect.contains(startPoint) || rect.contains(endPoint) {
            return true
        }

        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        var lowerBound: CGFloat = 0
        var upperBound: CGFloat = 1
        let boundaries = [
            (coefficient: -deltaX, distance: startPoint.x - rect.minX),
            (coefficient: deltaX, distance: rect.maxX - startPoint.x),
            (coefficient: -deltaY, distance: startPoint.y - rect.minY),
            (coefficient: deltaY, distance: rect.maxY - startPoint.y)
        ]

        for boundary in boundaries {
            if boundary.coefficient == 0 {
                guard boundary.distance >= 0 else { return false }
                continue
            }
            let ratio = boundary.distance / boundary.coefficient
            if boundary.coefficient < 0 {
                lowerBound = max(lowerBound, ratio)
            } else {
                upperBound = min(upperBound, ratio)
            }
            guard lowerBound <= upperBound else { return false }
        }
        return true
    }
}

/// Immutable render data derived from one graph/focus/viewport combination.
/// Layout construction is intentionally separated from pan and zoom state so
/// gesture frames only query spatial indices for nodes and edges near the viewport.
struct TaxonomyConstellationScene {
    let revision: Int
    let layout: TaxonomyConstellationLayout
    let visibleNodeIDs: Set<String>

    private struct PositionedNode {
        let node: TaxonomyTreeNode
        let position: CGPoint
        let order: Int
    }

    private struct SpatialCell: Hashable {
        let column: Int
        let row: Int
    }

    private indirect enum EdgeSpatialIndex {
        case empty
        case leaf(bounds: CGRect, indices: [Int])
        case branch(bounds: CGRect, first: EdgeSpatialIndex, second: EdgeSpatialIndex)

        var bounds: CGRect {
            switch self {
            case .empty:
                return .null
            case .leaf(let bounds, _), .branch(let bounds, _, _):
                return bounds
            }
        }

        func collectEdgeIndices(intersecting rect: CGRect, into indices: inout [Int]) {
            guard bounds.intersects(rect) else { return }
            switch self {
            case .empty:
                return
            case .leaf(_, let leafIndices):
                indices.append(contentsOf: leafIndices)
            case .branch(_, let first, let second):
                first.collectEdgeIndices(intersecting: rect, into: &indices)
                second.collectEdgeIndices(intersecting: rect, into: &indices)
            }
        }
    }

    private static let spatialCellSize: CGFloat = 512
    private static let maximumEdgesPerLeaf = 12
    private let positionedNodes: [PositionedNode]
    private let nodesByCell: [SpatialCell: [PositionedNode]]
    private let edgeSegments: [TaxonomyConstellationEdgeSegment]
    private let edgeSpatialIndex: EdgeSpatialIndex

    init(
        revision: Int,
        graph: TaxonomyTreeGraph,
        layoutNodeIDs: Set<String>,
        layout: TaxonomyConstellationLayout
    ) {
        self.revision = revision
        self.layout = layout
        self.visibleNodeIDs = layoutNodeIDs

        let positionedNodes = graph.nodes.enumerated().compactMap { index, node -> PositionedNode? in
            guard layoutNodeIDs.contains(node.id),
                  let position = layout.positions[node.id] else { return nil }
            return PositionedNode(node: node, position: position, order: index)
        }
        self.positionedNodes = positionedNodes
        self.nodesByCell = Dictionary(grouping: positionedNodes) { positionedNode in
            Self.spatialCell(containing: positionedNode.position)
        }

        var edgeSegments: [TaxonomyConstellationEdgeSegment] = []
        for edge in graph.edges {
            guard layoutNodeIDs.contains(edge.from),
                  layoutNodeIDs.contains(edge.to),
                  let endNode = graph.node(id: edge.to),
                  let startPoint = layout.positions[edge.from],
                  let endPoint = layout.positions[edge.to],
                  Self.isFinite(startPoint),
                  Self.isFinite(endPoint) else { continue }
            let segment = TaxonomyConstellationEdgeSegment(
                edge: edge,
                endNode: endNode,
                startPoint: startPoint,
                endPoint: endPoint
            )
            edgeSegments.append(segment)
        }
        self.edgeSegments = edgeSegments
        self.edgeSpatialIndex = Self.makeEdgeSpatialIndex(
            indices: Array(edgeSegments.indices),
            segments: edgeSegments
        )
    }

    func nodes(in rect: CGRect) -> [TaxonomyTreeNode] {
        guard !positionedNodes.isEmpty, Self.isFinite(rect) else { return [] }

        let minimumCell = Self.spatialCell(containing: CGPoint(x: rect.minX, y: rect.minY))
        let maximumCell = Self.spatialCell(containing: CGPoint(x: rect.maxX, y: rect.maxY))
        let columnCount = maximumCell.column - minimumCell.column + 1
        let rowCount = maximumCell.row - minimumCell.row + 1
        guard columnCount > 0, rowCount > 0 else { return [] }

        // A very wide query is cheaper as one linear pass than walking a mostly
        // empty grid (for example, a tiny graph zoomed fully into view).
        let occupiedCellCount = max(1, nodesByCell.count)
        if columnCount > occupiedCellCount * 4
            || rowCount > occupiedCellCount * 4
            || columnCount * rowCount > occupiedCellCount * 8 {
            return positionedNodes
                .filter { rect.contains($0.position) }
                .map(\.node)
        }

        var candidates: [PositionedNode] = []
        for row in minimumCell.row...maximumCell.row {
            for column in minimumCell.column...maximumCell.column {
                candidates.append(contentsOf: nodesByCell[
                    SpatialCell(column: column, row: row),
                    default: []
                ])
            }
        }

        return candidates
            .filter { rect.contains($0.position) }
            .sorted { $0.order < $1.order }
            .map(\.node)
    }

    func edges(
        in rect: CGRect,
        visibleNodeIDs: Set<String>
    ) -> [TaxonomyConstellationEdgeSegment] {
        guard !edgeSegments.isEmpty, Self.isFinite(rect) else { return [] }

        var candidateIndices: [Int] = []
        edgeSpatialIndex.collectEdgeIndices(intersecting: rect, into: &candidateIndices)

        return candidateIndices.sorted().compactMap { index in
            let segment = edgeSegments[index]
            guard visibleNodeIDs.contains(segment.edge.from),
                  visibleNodeIDs.contains(segment.edge.to),
                  segment.intersects(rect) else { return nil }
            return segment
        }
    }

    private static func spatialCell(containing point: CGPoint) -> SpatialCell {
        SpatialCell(
            column: Int(floor(point.x / spatialCellSize)),
            row: Int(floor(point.y / spatialCellSize))
        )
    }

    private static func makeEdgeSpatialIndex(
        indices: [Int],
        segments: [TaxonomyConstellationEdgeSegment]
    ) -> EdgeSpatialIndex {
        guard !indices.isEmpty else { return .empty }
        let bounds = indices.reduce(CGRect.null) {
            $0.union(segments[$1].bounds)
        }
        guard indices.count > maximumEdgesPerLeaf else {
            return .leaf(bounds: bounds, indices: indices)
        }

        let sortsHorizontally = bounds.width >= bounds.height
        let sortedIndices = indices.sorted { lhs, rhs in
            let lhsBounds = segments[lhs].bounds
            let rhsBounds = segments[rhs].bounds
            let lhsCenter = sortsHorizontally ? lhsBounds.midX : lhsBounds.midY
            let rhsCenter = sortsHorizontally ? rhsBounds.midX : rhsBounds.midY
            return lhsCenter == rhsCenter ? lhs < rhs : lhsCenter < rhsCenter
        }
        let midpoint = sortedIndices.count / 2
        return .branch(
            bounds: bounds,
            first: makeEdgeSpatialIndex(
                indices: Array(sortedIndices[..<midpoint]),
                segments: segments
            ),
            second: makeEdgeSpatialIndex(
                indices: Array(sortedIndices[midpoint...]),
                segments: segments
            )
        )
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.minX.isFinite
            && rect.minY.isFinite
            && rect.maxX.isFinite
            && rect.maxY.isFinite
    }
}
