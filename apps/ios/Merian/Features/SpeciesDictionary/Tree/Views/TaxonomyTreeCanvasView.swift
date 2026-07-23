import SwiftUI

struct TaxonomyTreeCanvasView: View {
    let onOpenSpecies: (SpeciesDictionaryRoute) -> Void
    let showsNavigationTitle: Bool

    @StateObject private var viewModel = TaxonomyTreeCanvasViewModel()

    init(
        showsNavigationTitle: Bool = true,
        onOpenSpecies: @escaping (SpeciesDictionaryRoute) -> Void
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.onOpenSpecies = onOpenSpecies
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.graph.nodes.isEmpty {
                stateWithScopeFilter { loadingState }
            } else if let errorMessage = viewModel.errorMessage, viewModel.graph.nodes.isEmpty {
                stateWithScopeFilter { errorState(message: errorMessage) }
            } else if viewModel.graph.nodes.isEmpty {
                stateWithScopeFilter { emptyState }
            } else {
                canvas
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(TaxonomyTreeCanvasTitleModifier(isEnabled: showsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.selectedTreeScope) {
            await viewModel.loadTree()
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let scene = viewModel.constellationScene(in: proxy.size)
            let visibleNodeIDs = scene.visibleNodeIDs
            let layout = scene.layout
            let selectedNode = viewModel.selectedNode
            let spotlightIDs = viewModel.spotlightNodeIDs
            let visibleRect = viewModel.visibleContentRect(in: proxy.size)
            let viewportNodes = scene.nodes(
                in: visibleRect.insetBy(dx: -140, dy: -140)
            ).filter { visibleNodeIDs.contains($0.id) }
            let viewportEdges = scene.edges(
                in: visibleRect.insetBy(dx: -140, dy: -140),
                visibleNodeIDs: visibleNodeIDs
            )

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                TaxonomyConstellationStarfield()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                TaxonomyConstellationClusterHalos(
                    graph: viewModel.graph,
                    positions: layout.positions,
                    visibleNodeIDs: visibleNodeIDs,
                    scale: viewModel.scale
                )
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(viewModel.scale, anchor: .topLeading)
                .offset(viewModel.currentOffset)

                TaxonomyConstellationEdgesCanvas(
                    segments: viewportEdges,
                    spotlightIDs: spotlightIDs,
                    selectedNodeID: viewModel.selectedNodeID,
                    scale: viewModel.scale,
                    contentOffset: viewModel.currentOffset
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()

                ZStack(alignment: .topLeading) {
                    ForEach(viewportNodes) { node in
                        TaxonomyConstellationNodeView(
                            node: node,
                            scale: viewModel.scale,
                            branchTint: TaxonomyConstellationPalette.tint(for: node),
                            isSelected: selectedNode?.id == node.id,
                            isSpotlighted: spotlightIDs.isEmpty || spotlightIDs.contains(node.id),
                            isFocused: viewModel.focusedNodeID == node.id,
                            action: {
                                if let route = node.dictionaryRoute {
                                    onOpenSpecies(route)
                                } else {
                                    withAnimation(.snappy(duration: 0.28)) {
                                        viewModel.focus(on: node.id, viewportSize: proxy.size)
                                    }
                                }
                            }
                        )
                        .position(layout.positions[node.id] ?? .zero)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .scaleEffect(viewModel.scale, anchor: .topLeading)
                .offset(viewModel.currentOffset)
                .contentShape(Rectangle())
                .animation(.snappy(duration: 0.22), value: viewModel.focusedNodeID)
                .animation(.snappy(duration: 0.22), value: viewModel.selectedNodeID)

                if viewModel.breadcrumbText != nil {
                    TaxonomyTreeControlBar(
                        breadcrumb: viewModel.breadcrumbText,
                        leadingInset: 30
                    )
                    .frame(width: proxy.size.width, alignment: .topLeading)
                    .padding(.top, 58)
                    .padding(.bottom, 12)
                }

                TaxonomyTreeScopeFilterBar(
                    activeScope: viewModel.selectedTreeScope,
                    onSelection: { scope in
                        viewModel.selectTreeScope(scope)
                    }
                )

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 82)
                        .padding(.trailing, 16)
                }

                TaxonomyTreeFloatingControls(
                    zoomPercentage: viewModel.zoomPercentage,
                    canClearFocus: viewModel.focusedNodeID != nil || viewModel.selectedNodeID != nil,
                    onZoomOut: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.zoom(
                                by: 0.78,
                                viewportSize: proxy.size,
                                contentSize: layout.size
                            )
                        }
                    },
                    onZoomIn: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.zoom(
                                by: 1.35,
                                viewportSize: proxy.size,
                                contentSize: layout.size
                            )
                        }
                    },
                    onReset: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.resetView(positions: layout.positions, viewportSize: proxy.size)
                        }
                    }
                )
                .position(
                    x: max(58, proxy.size.width - 42),
                    y: max(220, proxy.size.height - 120)
                )
                .zIndex(4)

            }
            .simultaneousGesture(
                viewModel.canvasGesture(
                    in: proxy.size,
                    contentSize: layout.size
                )
            )
            .onAppear {
                viewModel.positionInitialViewportIfNeeded(positions: layout.positions, viewportSize: proxy.size)
            }
            .onChange(of: scene.revision) {
                viewModel.reconcileLayoutChange(
                    to: scene.layout.positions,
                    viewportSize: proxy.size
                )
            }
            .onChange(of: proxy.size) { _, viewportSize in
                viewModel.positionInitialViewportIfNeeded(positions: layout.positions, viewportSize: viewportSize)
            }
        }
    }

    private func stateWithScopeFilter<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            content()

            TaxonomyTreeScopeFilterBar(
                activeScope: viewModel.selectedTreeScope,
                onSelection: { scope in
                    viewModel.selectTreeScope(scope)
                }
            )
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Mapping constellation")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        switch viewModel.selectedTreeScope {
        case .allSpecies:
            ContentUnavailableView(
                "No dictionary taxonomy yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("The public taxonomy constellation will appear here as species are added.")
            )
        case .myScans:
            ContentUnavailableView(
                "No scanned taxonomy yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("The constellation appears after your biological scans are matched to dictionary species.")
            )
        }
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label(errorTitle, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await viewModel.loadTree(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var errorTitle: String {
        switch viewModel.selectedTreeScope {
        case .allSpecies: "Public tree unavailable"
        case .myScans: "Scanned tree unavailable"
        }
    }
}

private struct TaxonomyConstellationSceneCacheKey: Equatable {
    let graphRevision: Int
    let focusedNodeID: String?
    let minimumSize: CGSize
}

private struct TaxonomyConstellationSpotlightCacheKey: Equatable {
    let graphRevision: Int
    let selectedNodeID: String?
}

@MainActor
final class TaxonomyTreeCanvasViewModel: ObservableObject {
    @Published private(set) var graph: TaxonomyTreeGraph = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedTreeScope: SpeciesDictionaryTreeScope = .allSpecies
    @Published var selectedNodeID: String?
    @Published var focusedNodeID: String?
    @Published var offset: CGSize = .zero
    @Published var dragOffset: CGSize = .zero
    @Published var scale: CGFloat = 1.1
    @Published var baseScale: CGFloat = 1.1

    private let minScale: CGFloat = 0.64
    private let absoluteMinScale: CGFloat = 0.08
    private let maxScale: CGFloat = 4
    private let initialScale: CGFloat = 1.1
    private let topRootViewportY: CGFloat = 180
    private let graphLoader: (SpeciesDictionaryTreeScope) async throws -> TaxonomyTreeGraph
    private var lastMagnification: CGFloat?
    private var hasPositionedInitialViewport = false
    private var cachedGraphsByScope: [SpeciesDictionaryTreeScope: TaxonomyTreeGraph] = [:]
    private var graphRevision = 0
    private var sceneRevision = 0
    private var cachedSceneKey: TaxonomyConstellationSceneCacheKey?
    private var cachedScene: TaxonomyConstellationScene?
    private var cachedSpotlightKey: TaxonomyConstellationSpotlightCacheKey?
    private var cachedSpotlightNodeIDs: Set<String> = []

    init(
        graphLoader: @escaping (SpeciesDictionaryTreeScope) async throws -> TaxonomyTreeGraph = { scope in
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryTree(scope: scope)
            return TaxonomyTreeGraphBuilder.build(from: response.data)
        }
    ) {
        self.graphLoader = graphLoader
    }

    var selectedNode: TaxonomyTreeNode? {
        graph.node(id: selectedNodeID)
    }

    /// Layout coordinates must not change while a pinch is in progress. The active
    /// branch is laid out once; zoom only reveals more of the nodes already in it.
    var layoutNodeIDs: Set<String> {
        guard let focusedNodeID, graph.node(id: focusedNodeID) != nil else {
            return Set(graph.nodes.map(\.id))
        }

        var nodeIDs: Set<String> = [focusedNodeID]
        nodeIDs.formUnion(graph.ancestorIDs(of: focusedNodeID))
        nodeIDs.formUnion(graph.descendantIDs(of: focusedNodeID))
        return nodeIDs
    }

    var spotlightNodeIDs: Set<String> {
        let cacheKey = TaxonomyConstellationSpotlightCacheKey(
            graphRevision: graphRevision,
            selectedNodeID: selectedNodeID
        )
        if cachedSpotlightKey == cacheKey {
            return cachedSpotlightNodeIDs
        }

        guard let selectedNodeID else {
            cachedSpotlightKey = cacheKey
            cachedSpotlightNodeIDs = []
            return []
        }
        var ids = graph.connectedIDs(for: selectedNodeID)
        ids.formUnion(graph.ancestorIDs(of: selectedNodeID))
        ids.formUnion(graph.descendantIDs(of: selectedNodeID))
        cachedSpotlightKey = cacheKey
        cachedSpotlightNodeIDs = ids
        return ids
    }

    var breadcrumbText: String? {
        let anchorID = selectedNodeID ?? focusedNodeID
        guard let anchorID, let node = graph.node(id: anchorID) else { return nil }
        let titles = graph.ancestorIDs(of: anchorID)
            .compactMap { graph.node(id: $0) }
            .sorted { $0.rank.sortIndex < $1.rank.sortIndex }
            .map(\.title) + [node.title]
        return titles.joined(separator: " / ").nilIfEmpty
    }

    var currentOffset: CGSize {
        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
    }

    var zoomPercentage: Int {
        Int((scale / initialScale * 100).rounded())
    }

    func constellationScene(in viewportSize: CGSize) -> TaxonomyConstellationScene {
        let minimumSize = normalizedLayoutSize(viewportSize)
        let validFocusedNodeID = graph.node(id: focusedNodeID) == nil ? nil : focusedNodeID
        let cacheKey = TaxonomyConstellationSceneCacheKey(
            graphRevision: graphRevision,
            focusedNodeID: validFocusedNodeID,
            minimumSize: minimumSize
        )
        if cachedSceneKey == cacheKey, let cachedScene {
            return cachedScene
        }

        let nodeIDs = layoutNodeIDs
        let layout = TaxonomyConstellationLayout.make(
            graph: graph,
            visibleNodeIDs: nodeIDs,
            focusedNodeID: validFocusedNodeID,
            minimumSize: minimumSize
        )
        sceneRevision &+= 1
        let scene = TaxonomyConstellationScene(
            revision: sceneRevision,
            graph: graph,
            layoutNodeIDs: nodeIDs,
            layout: layout
        )
        cachedSceneKey = cacheKey
        cachedScene = scene
        return scene
    }

    func canvasGesture(in viewportSize: CGSize, contentSize: CGSize) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 2),
            MagnifyGesture()
        )
            .onChanged { [weak self] value in
                guard let self else { return }
                if let magnification = value.second {
                    if lastMagnification == nil {
                        dragOffset = .zero
                    }

                    let anchor = clampedAnchor(magnification.startLocation, in: viewportSize)
                    updateMagnification(
                        magnification.magnification,
                        anchoredAt: anchor,
                        minimumScale: minimumScale(
                            for: viewportSize,
                            contentSize: contentSize
                        )
                    )
                    return
                }

                if lastMagnification == nil {
                    dragOffset = value.first?.translation ?? .zero
                }
            }
            .onEnded { [weak self] value in
                guard let self else { return }
                if lastMagnification != nil || value.second != nil {
                    endMagnification()
                } else if let drag = value.first {
                    offset.width += drag.translation.width
                    offset.height += drag.translation.height
                    dragOffset = .zero
                }
            }
    }

    func loadTree(force: Bool = false) async {
        let scope = selectedTreeScope
        if !force, let cachedGraph = cachedGraphsByScope[scope] {
            applyGraph(cachedGraph)
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let loadedGraph = try await graphLoader(scope)
            cachedGraphsByScope[scope] = loadedGraph
            if selectedTreeScope == scope {
                if applyGraph(loadedGraph) {
                    hasPositionedInitialViewport = false
                }
            }
        } catch {
            if selectedTreeScope == scope {
                errorMessage = ExploreErrorFormatter.message(for: error)
            }
        }
        if selectedTreeScope == scope {
            isLoading = false
        }
    }

    func selectTreeScope(_ scope: SpeciesDictionaryTreeScope) {
        guard scope != selectedTreeScope else { return }
        selectedTreeScope = scope
        selectedNodeID = nil
        focusedNodeID = nil
        offset = .zero
        dragOffset = .zero
        scale = initialScale
        baseScale = initialScale
        errorMessage = nil
        hasPositionedInitialViewport = false

        if let cachedGraph = cachedGraphsByScope[scope] {
            applyGraph(cachedGraph)
            isLoading = false
        } else {
            applyGraph(.empty)
            isLoading = true
        }
    }

    func focus(on nodeID: String, viewportSize: CGSize) {
        setScale(
            graph.node(id: nodeID)?.isSpecies == true ? 2.6 : 1.35,
            anchoredAt: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        )
        focusedNodeID = nodeID
        selectedNodeID = nodeID
        HapticManager.shared.triggerSelectionPulse()
    }

    func clearFocus() {
        focusedNodeID = nil
        selectedNodeID = nil
        hasPositionedInitialViewport = false
        HapticManager.shared.triggerSelectionPulse()
    }

    func resetView(positions: [String: CGPoint]? = nil, viewportSize: CGSize? = nil) {
        selectedNodeID = nil
        focusedNodeID = nil
        dragOffset = .zero
        scale = initialScale
        baseScale = scale
        if let positions, let viewportSize, centerTopRoot(positions: positions, viewportSize: viewportSize) {
            hasPositionedInitialViewport = true
        } else {
            offset = .zero
            hasPositionedInitialViewport = false
        }
    }

    func zoom(by multiplier: CGFloat, viewportSize: CGSize, contentSize: CGSize? = nil) {
        zoom(
            by: multiplier,
            anchoredAt: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2),
            minimumScale: contentSize.map {
                minimumScale(for: viewportSize, contentSize: $0)
            }
        )
    }

    func zoom(by multiplier: CGFloat, anchoredAt anchor: CGPoint, minimumScale: CGFloat? = nil) {
        setScale(
            clampedScale(scale * multiplier, minimumScale: minimumScale),
            anchoredAt: anchor,
            minimumScale: minimumScale
        )
    }

    func updateMagnification(
        _ magnification: CGFloat,
        anchoredAt anchor: CGPoint,
        minimumScale: CGFloat? = nil
    ) {
        guard magnification.isFinite, magnification > 0 else { return }
        let previousMagnification = lastMagnification ?? 1
        let incrementalMagnification = magnification / previousMagnification
        lastMagnification = magnification
        setScale(
            clampedScale(scale * incrementalMagnification, minimumScale: minimumScale),
            anchoredAt: anchor,
            minimumScale: minimumScale
        )
    }

    func endMagnification() {
        baseScale = scale
        lastMagnification = nil
        dragOffset = .zero
    }

    func setScale(_ value: CGFloat, anchoredAt anchor: CGPoint, minimumScale: CGFloat? = nil) {
        applyScale(
            clampedScale(value, minimumScale: minimumScale),
            anchoredAt: anchor,
            startingScale: scale,
            startingOffset: currentOffset
        )
        baseScale = scale
    }

    func setScale(_ value: CGFloat) {
        scale = clampedScale(value)
        baseScale = scale
    }

    func center(nodeID: String, positions: [String: CGPoint], viewportSize: CGSize) {
        guard let position = positions[nodeID] else { return }
        offset = CGSize(
            width: viewportSize.width / 2 - position.x * scale,
            height: viewportSize.height / 2 - position.y * scale
        )
        dragOffset = .zero
    }

    func centerTop(nodeID: String, positions: [String: CGPoint], viewportSize: CGSize) {
        guard let position = positions[nodeID] else { return }
        offset = CGSize(
            width: viewportSize.width / 2 - position.x * scale,
            height: topRootViewportY - position.y * scale
        )
        dragOffset = .zero
    }

    func positionInitialViewportIfNeeded(positions: [String: CGPoint], viewportSize: CGSize) {
        guard !hasPositionedInitialViewport else { return }
        guard centerTopRoot(positions: positions, viewportSize: viewportSize) else { return }
        hasPositionedInitialViewport = true
    }

    func reconcileLayoutChange(
        to positions: [String: CGPoint],
        viewportSize: CGSize
    ) {
        if let anchorNodeID = focusedNodeID ?? selectedNodeID {
            center(nodeID: anchorNodeID, positions: positions, viewportSize: viewportSize)
        } else {
            positionInitialViewportIfNeeded(positions: positions, viewportSize: viewportSize)
        }
    }

    func visibleContentRect(in viewportSize: CGSize) -> CGRect {
        let offset = currentOffset
        return CGRect(
            x: -offset.width / scale,
            y: -offset.height / scale,
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )
    }

    func minimumScale(for viewportSize: CGSize, contentSize: CGSize) -> CGFloat {
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              contentSize.width > 0,
              contentSize.height > 0 else { return minScale }
        let usableViewport = CGSize(
            width: viewportSize.width * 0.9,
            height: max(240, viewportSize.height - 260)
        )
        let fitScale = min(
            usableViewport.width / contentSize.width,
            usableViewport.height / contentSize.height
        )
        return min(minScale, max(absoluteMinScale, fitScale))
    }

    private func clampedScale(_ value: CGFloat, minimumScale: CGFloat? = nil) -> CGFloat {
        min(maxScale, max(minimumScale ?? minScale, value))
    }

    @discardableResult
    private func applyGraph(_ nextGraph: TaxonomyTreeGraph) -> Bool {
        guard graph != nextGraph else { return false }
        graph = nextGraph
        graphRevision &+= 1
        cachedSceneKey = nil
        cachedScene = nil
        cachedSpotlightKey = nil
        cachedSpotlightNodeIDs = []
        return true
    }

    private func normalizedLayoutSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? ceil(max(0, size.width)) : 0,
            height: size.height.isFinite ? ceil(max(0, size.height)) : 0
        )
    }

    private func clampedAnchor(_ anchor: CGPoint, in viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(anchor.x, 0), max(viewportSize.width, 0)),
            y: min(max(anchor.y, 0), max(viewportSize.height, 0))
        )
    }

    @discardableResult
    private func centerTopRoot(positions: [String: CGPoint], viewportSize: CGSize) -> Bool {
        guard let rootNodeID = graph.rootNodeIDs.first, positions[rootNodeID] != nil else {
            return false
        }
        centerTop(nodeID: rootNodeID, positions: positions, viewportSize: viewportSize)
        return true
    }

    private func applyScale(
        _ nextScale: CGFloat,
        anchoredAt anchor: CGPoint,
        startingScale: CGFloat,
        startingOffset: CGSize
    ) {
        guard startingScale > 0 else {
            scale = nextScale
            return
        }

        let anchoredContentPoint = CGPoint(
            x: (anchor.x - startingOffset.width) / startingScale,
            y: (anchor.y - startingOffset.height) / startingScale
        )
        scale = nextScale
        offset = CGSize(
            width: anchor.x - anchoredContentPoint.x * nextScale,
            height: anchor.y - anchoredContentPoint.y * nextScale
        )
        dragOffset = .zero
    }
}

private struct TaxonomyConstellationStarfield: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<180 {
                let xFraction = CGFloat((index * 89 + 17) % 997) / 997
                let yFraction = CGFloat((index * 149 + 31) % 991) / 991
                let diameter = CGFloat(1 + (index % 3)) * 0.72
                let rect = CGRect(
                    x: xFraction * size.width,
                    y: yFraction * size.height,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.secondary.opacity(index.isMultiple(of: 5) ? 0.16 : 0.08))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TaxonomyConstellationClusterHalos: View {
    let graph: TaxonomyTreeGraph
    let positions: [String: CGPoint]
    let visibleNodeIDs: Set<String>
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleRoots) { root in
                if let position = positions[root.id] {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    TaxonomyConstellationPalette.tint(for: root).opacity(0.13),
                                    TaxonomyConstellationPalette.tint(for: root).opacity(0.035),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 12,
                                endRadius: 170
                            )
                        )
                        .frame(width: 340, height: 340)
                        .scaleEffect(1 / max(1, scale))
                        .position(position)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var visibleRoots: [TaxonomyTreeNode] {
        graph.rootNodeIDs.compactMap { rootID in
            guard visibleNodeIDs.contains(rootID) else { return nil }
            return graph.node(id: rootID)
        }
    }
}

private struct TaxonomyConstellationEdgesCanvas: View, Animatable {
    let segments: [TaxonomyConstellationEdgeSegment]
    let spotlightIDs: Set<String>
    let selectedNodeID: String?
    var scale: CGFloat
    var contentOffset: CGSize

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                scale,
                AnimatablePair(contentOffset.width, contentOffset.height)
            )
        }
        set {
            scale = newValue.first
            contentOffset = CGSize(
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    var body: some View {
        Canvas { context, _ in
            for segment in segments {
                let edge = segment.edge
                let isSpotlighted = spotlightIDs.isEmpty ||
                    (spotlightIDs.contains(edge.from) && spotlightIDs.contains(edge.to))
                let isSelectedEdge = selectedNodeID == edge.from || selectedNodeID == edge.to
                var path = Path()
                path.move(to: screenPoint(for: segment.startPoint))
                path.addLine(to: screenPoint(for: segment.endPoint))
                let tint = TaxonomyConstellationPalette.tint(for: segment.endNode)
                let semanticScale = max(0.15, scale)
                let screenScale = scale / semanticScale
                let lineageWeight = min(
                    2.4,
                    0.72 + CGFloat(log10(Double(max(1, segment.endNode.speciesCount)))) * 0.58
                ) * screenScale
                if isSelectedEdge {
                    context.stroke(
                        path,
                        with: .color(tint.opacity(0.14)),
                        style: StrokeStyle(
                            lineWidth: lineageWeight + 6 * screenScale,
                            lineCap: .round
                        )
                    )
                }
                context.stroke(
                    path,
                    with: .color(isSpotlighted ? tint.opacity(isSelectedEdge ? 0.82 : 0.38) : Color.secondary.opacity(0.09)),
                    style: StrokeStyle(
                        lineWidth: isSpotlighted ? lineageWeight : 0.72 * screenScale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func screenPoint(for contentPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: contentPoint.x * scale + contentOffset.width,
            y: contentPoint.y * scale + contentOffset.height
        )
    }
}

private enum TaxonomyConstellationPalette {
    static func tint(for node: TaxonomyTreeNode) -> Color {
        let kingdom = (node.lineage?.kingdom ?? (node.rank == .kingdom ? node.title : ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch kingdom {
        case "animalia": return Color.blue
        case "plantae": return Color.green
        case "fungi": return Color.purple
        case "chromista": return Color.teal
        case "bacteria": return Color.cyan
        case "protozoa": return Color.indigo
        case "amoebozoa": return Color.pink
        default: return Color.accentColor
        }
    }
}

private struct TaxonomyTreeScopeFilterBar: View {
    let activeScope: SpeciesDictionaryTreeScope
    let onSelection: (SpeciesDictionaryTreeScope) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpeciesDictionaryTreeScope.allCases, id: \.self) { scope in
                    scopePill(scope)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func scopePill(_ scope: SpeciesDictionaryTreeScope) -> some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            onSelection(scope)
        } label: {
            Text(scope.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(activeScope == scope ? Color(uiColor: .systemBackground) : Color.primary)
                .background {
                    if activeScope == scope {
                        Capsule().fill(Color.primary)
                    } else {
                        Capsule().fill(.regularMaterial)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activeScope == scope ? .isSelected : [])
    }
}

private struct TaxonomyTreeControlBar: View {
    let breadcrumb: String?
    let leadingInset: CGFloat

    var body: some View {
        if let breadcrumb {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(breadcrumb)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, leadingInset)
                    .padding(.trailing, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }
}

private struct TaxonomyTreeFloatingControls: View {
    let zoomPercentage: Int
    let canClearFocus: Bool
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("\(zoomPercentage)%")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 48, height: 24)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.75)
                }
                .accessibilityLabel("Zoom level")
                .accessibilityValue("\(zoomPercentage) percent")

            controlButton(systemImage: "plus.magnifyingglass", action: onZoomIn, label: "Zoom in")
            controlButton(systemImage: "minus.magnifyingglass", action: onZoomOut, label: "Zoom out")
            controlButton(
                systemImage: "scope",
                action: onReset,
                label: canClearFocus ? "Return to constellation overview" : "Recenter constellation"
            )
        }
    }

    private func controlButton(systemImage: String, action: @escaping () -> Void, label: String) -> some View {
        Button {
            HapticManager.shared.triggerLightImpact(intensity: 0.48)
            action()
        } label: {
            controlIcon(systemImage)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .circularMaterialControl(
                    size: 46,
                    material: .ultraThinMaterial,
                    colorScheme: .dark,
                    borderColor: .white.opacity(0.18),
                    borderWidth: 0.75
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }

    private func controlIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
    }
}

private struct TaxonomyConstellationNodeView: View {
    let node: TaxonomyTreeNode
    let scale: CGFloat
    let branchTint: Color
    let isSelected: Bool
    let isSpotlighted: Bool
    let isFocused: Bool
    let action: () -> Void

    private var style: TaxonomyConstellationNodeStyle {
        TaxonomyConstellationNodeStyle.style(for: node, scale: scale)
    }

    var body: some View {
        VStack(spacing: 6) {
            nodeMark

            if style.showsTitle || isSelected || isFocused {
                Text(node.title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(node.isSpecies ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
            }

            if (style.showsTitle && style.showsMetadata) || isSelected || isFocused {
                Text(metadataText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic(node.isSpecies)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: style.showsTitle || isSelected || isFocused ? style.labelWidth : max(28, style.diameter))
        .contentShape(Rectangle())
        .opacity(isSpotlighted ? 1 : 0.24)
        .scaleEffect(isSelected || isFocused ? 1.06 : 1)
        .scaleEffect(1 / max(0.4, scale))
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(node.isSpecies ? "Centers this species" : "Zooms into this branch")
        .accessibilityAction {
            action()
        }
    }

    @ViewBuilder
    private var nodeMark: some View {
        ZStack {
            if node.isSpecies && style.showsSpeciesImage {
                thumbnail
            } else {
                TaxonomyConstellationGlyph(
                    node: node,
                    tint: branchTint,
                    diameter: style.diameter
                )
            }

            if isSelected || isFocused {
                Circle()
                    .stroke(branchTint.opacity(0.2), lineWidth: 8)
                    .padding(-7)
                Circle()
                    .strokeBorder(branchTint, lineWidth: isFocused ? 2.6 : 2)
            }
        }
        .frame(width: style.diameter, height: style.diameter)
        .shadow(
            color: branchTint.opacity(isSelected || isFocused ? 0.34 : 0.12),
            radius: isSelected || isFocused ? 13 : 5
        )
    }

    private var thumbnail: some View {
        Group {
            if let url = ExternalReferenceImagePolicy.url(from: node.species?.referenceImageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
        .frame(width: style.diameter, height: style.diameter)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(branchTint.opacity(0.5), lineWidth: 1.2)
        }
    }

    private var placeholderThumbnail: some View {
        Circle()
            .fill(branchTint.opacity(0.16))
            .overlay {
                Image(systemName: "leaf.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(branchTint)
            }
    }

    private var titleFont: Font {
        switch node.rank {
        case .kingdom: .caption.weight(.bold)
        case .phylum, .className: .caption2.weight(.bold)
        case .order, .family, .genus, .species: .caption2.weight(.semibold)
        }
    }

    private var metadataText: String {
        if node.isSpecies {
            return node.subtitle ?? "Species"
        }
        return "\(node.rank.title) · \(node.speciesCount)"
    }

    private var accessibilityLabel: String {
        if node.isSpecies {
            return "\(node.title), \(node.subtitle ?? "Species")"
        }
        return "\(node.title), \(node.rank.title), \(node.speciesCount) species"
    }
}

private struct TaxonomyConstellationGlyph: View {
    let node: TaxonomyTreeNode
    let tint: Color
    let diameter: CGFloat

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            context.fill(Path(ellipseIn: bounds), with: .color(tint.opacity(0.16)))
            context.stroke(
                Path(ellipseIn: bounds.insetBy(dx: 1, dy: 1)),
                with: .color(tint.opacity(0.68)),
                lineWidth: 1.35
            )

            let ringInset = max(7, radius * 0.25)
            context.stroke(
                Path(ellipseIn: bounds.insetBy(dx: ringInset, dy: ringInset)),
                with: .color(tint.opacity(0.22)),
                lineWidth: 0.9
            )

            let rayCount = max(3, min(8, node.childCount))
            let phase = phaseAngle
            for index in 0..<rayCount {
                let angle = phase + CGFloat(index) * 2 * CGFloat.pi / CGFloat(rayCount)
                let innerRadius = radius * 0.22
                let outerRadius = radius * 0.63
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                ))
                context.stroke(path, with: .color(tint.opacity(0.32)), lineWidth: 0.85)
            }

            let dotCount = max(1, min(6, node.childCount))
            for index in 0..<dotCount {
                let angle = phase + CGFloat(index) * 2 * CGFloat.pi / CGFloat(dotCount)
                let dotRadius = radius * 0.64
                let dotCenter = CGPoint(
                    x: center.x + cos(angle) * dotRadius,
                    y: center.y + sin(angle) * dotRadius
                )
                let dotDiameter = max(3.5, diameter * 0.075)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dotCenter.x - dotDiameter / 2,
                        y: dotCenter.y - dotDiameter / 2,
                        width: dotDiameter,
                        height: dotDiameter
                    )),
                    with: .color(tint.opacity(0.9))
                )
            }

            let coreDiameter = radius * 0.34
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - coreDiameter / 2,
                    y: center.y - coreDiameter / 2,
                    width: coreDiameter,
                    height: coreDiameter
                )),
                with: .color(tint.opacity(0.9))
            )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var phaseAngle: CGFloat {
        let scalarSum = node.id.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return CGFloat(scalarSum % 360) * CGFloat.pi / 180
    }
}

private struct TaxonomyConstellationNodeStyle {
    let diameter: CGFloat
    let labelWidth: CGFloat
    let showsTitle: Bool
    let showsMetadata: Bool
    let showsSpeciesImage: Bool

    static func style(for node: TaxonomyTreeNode, scale: CGFloat) -> TaxonomyConstellationNodeStyle {
        let baseDiameter = diameter(for: node.rank, scale: scale)
        let titleRankLimit = titleRankLimit(for: scale)

        return TaxonomyConstellationNodeStyle(
            diameter: baseDiameter,
            labelWidth: node.isSpecies ? 136 : max(116, baseDiameter + 42),
            showsTitle: node.rank.sortIndex <= titleRankLimit,
            showsMetadata: scale >= 1.8,
            showsSpeciesImage: node.isSpecies && scale >= 2.6
        )
    }

    private static func diameter(for rank: TaxonomyTreeRank, scale: CGFloat) -> CGFloat {
        if scale < 1 {
            switch rank {
            case .kingdom: return 58
            case .phylum: return 44
            case .className: return 34
            case .order: return 24
            case .family: return 17
            case .genus: return 12
            case .species: return 8
            }
        }

        if scale < 1.6 {
            switch rank {
            case .kingdom: return 68
            case .phylum: return 56
            case .className: return 46
            case .order: return 36
            case .family: return 27
            case .genus: return 19
            case .species: return 11
            }
        }

        if scale < 2.4 {
            switch rank {
            case .kingdom: return 74
            case .phylum: return 64
            case .className: return 56
            case .order: return 48
            case .family: return 40
            case .genus: return 31
            case .species: return 18
            }
        }

        switch rank {
        case .kingdom: return 78
        case .phylum: return 70
        case .className: return 64
        case .order: return 58
        case .family: return 54
        case .genus: return 50
        case .species: return scale >= 2.6 ? 74 : 52
        }
    }

    private static func titleRankLimit(for scale: CGFloat) -> Int {
        if scale < 0.85 { return TaxonomyTreeRank.phylum.sortIndex }
        if scale < 1.2 { return TaxonomyTreeRank.order.sortIndex }
        if scale < 1.8 { return TaxonomyTreeRank.family.sortIndex }
        if scale < 2.6 { return TaxonomyTreeRank.genus.sortIndex }
        return TaxonomyTreeRank.species.sortIndex
    }
}

private struct TaxonomyTreeCanvasTitleModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationTitle("Tree of Life")
        } else {
            content
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
